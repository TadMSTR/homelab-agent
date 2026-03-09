# Backup Strategy

Claudebox has three backup mechanisms covering different scopes: system-level config and home directory via Backrest/restic, Claude Desktop–specific data via a custom script, and Docker appdata via the docker-stack-backup PM2 job. All three target an NFS mount on the storage server.

This doc covers what each job does, when it runs, and what it protects. Individual jobs are referenced elsewhere in the repo (PM2 ecosystem config, scripts directory), but this is the single place to understand the full backup picture.

## NFS Dependency

Every backup job on claudebox writes to the same NFS mount. If the mount is unavailable, all backups fail — so the mount is the first thing to verify when something looks wrong.

```
# /etc/fstab entry
STORAGE_IP:/mnt/storage/claudebox  /mnt/storage/claudebox  nfs  rw,nfsvers=3,rsize=1048576,wsize=1048576,timeo=14,_netdev  0  0
```

The `_netdev` flag ensures the mount waits for network availability at boot. Systemd auto-generates a mount unit (`mnt-storage-claudebox.mount`) from fstab, which Backrest uses as a hard dependency — it won't start until the NFS share is mounted. The other two jobs (claude backup script, docker-stack-backup) check mount availability at runtime and fail gracefully if it's missing. The resource-monitor PM2 job checks NFS mount health every 6 hours and alerts via push notification if it's down.

## Schedule Overview

| Time | Job | Scope |
|------|-----|-------|
| 1:00 AM | docker-stack-backup | Docker appdata + compose files |
| 2:00 AM | Backrest/restic | `/home/ted`, `/etc`, `/opt/Obsidian` |
| 3:00 AM | backup-claude.sh | Claude Desktop memory, config, extensions |

The ordering is intentional. Docker containers get backed up first (requires stopping and restarting them), then the system-level restic backup runs, then the Claude-specific data. Each job completes well before the next starts.

## Backrest / Restic — System Backups

[Backrest](https://github.com/garethgeorge/backrest) is a web UI orchestrator for restic. It handles scheduling, retention, prune, and integrity checks through a single interface. On claudebox it runs as a systemd service (as root) and manages a single restic repository on the NFS mount.

| Setting | Value |
|---------|-------|
| Binary | `/usr/local/bin/backrest` |
| WebUI | `http://HOST_IP:9898` |
| Service | systemd (`backrest.service`) |
| Runs as | root |
| Restic repo | `/mnt/storage/claudebox/restic-repo` (NFS) |

The systemd service has `Requires=mnt-storage-claudebox.mount` so Backrest won't attempt to start if the NFS share isn't available. Backrest downloads and manages its own restic binary — you don't install restic separately.

### Backup Plans

All three plans run daily at 2:00 AM local time with 90-day retention (keep last 90 snapshots).

**claudebox-home** backs up `/home/ted` — the most important plan. This covers repos, scripts, dotfiles, Claude Code memory files, and the prime directive checkout. Excludes are tuned to skip caches and ephemeral data that would bloat the repo without adding recovery value:

```
Excludes:
  .cache
  .local/share/Trash
  .gvfs
  thinclient_drives
  .config/Claude/vm_bundles
  .config/Claude/claude-code
  .config/Claude/claude-code-vm
  .config/Claude/Cache
  .config/Claude/Code Cache
  .config/thorium/Cache
  .config/discord/Cache
  .config/VSCodium/Cache
  .config/librewolf/cache
  .vscode-oss/extensions
```

`.gvfs` and `thinclient_drives` are GNOME/RDP virtual mounts that root can't read — they'll cause restic errors if not excluded. The Claude-specific excludes (`vm_bundles`, `claude-code`, `claude-code-vm`, `Cache`, `Code Cache`) are large and ephemeral; Claude Desktop recreates them on launch.

**claudebox-etc** backs up `/etc` — system configuration, fstab, systemd units, network config, cron, apt sources. No excludes. Small and fast.

**claudebox-opt** backs up `/opt/Obsidian` — the Obsidian AppImage install. No excludes.

### Maintenance

Backrest handles prune and integrity checks automatically:

- **Prune:** Monthly (1st of month), targets max 10% unused space in the restic repo
- **Integrity check:** Monthly (1st of month), runs `restic check` against the repo

Both run on a `CLOCK_LAST_RUN_TIME` schedule, meaning the timer starts from the last successful run rather than a fixed wall-clock time. This prevents missed runs from stacking up.

### API Access

Backrest exposes a ConnectRPC API on the same port as the WebUI. Useful for automation or monitoring scripts:

```bash
# Get full config (plans, repos, auth)
curl -s -X POST 'http://localhost:9898/v1.Backrest/GetConfig' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic BASE64_USER:PASS' \
  -d '{}'

# Get recent operations for a plan
curl -s -X POST 'http://localhost:9898/v1.Backrest/GetOperations' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Basic BASE64_USER:PASS' \
  -d '{"selector":{"planId":"claudebox-home"},"lastN":"5"}'
```

Auth uses HTTP Basic with credentials stored in `~/.config/backrest/api-creds` (format: `user:password`, one per line). The WebUI login uses a separate bcrypt-hashed user list in the Backrest config.

## Claude Desktop Backup Script

Backrest runs as root, but Claude Desktop's config and memory live in the user's home directory under `~/.config/Claude/`. While Backrest's `claudebox-home` plan does cover this path, the custom backup script (`~/scripts/backup-claude.sh`) adds a second layer with a different structure: a `latest/` directory that always reflects the current state (via rsync) plus dated snapshots for point-in-time recovery.

| Setting | Value |
|---------|-------|
| Script | `~/scripts/backup-claude.sh` |
| Schedule | Daily at 3:00 AM (user crontab) |
| Destination | `/mnt/storage/claudebox/claude-backup/` (NFS) |
| Retention | 90 days |
| Notifications | Push notification via ntfy on completion |

### What Gets Backed Up

- **`basic-memory/claude/`** — Basic Memory markdown knowledge base. The working notes layer between sessions.
- **`claude_desktop_config.json`** — MCP server configuration. Contains live API tokens — backed up to NFS only, never committed to git.
- **`Claude Extensions Settings/`** — Extension settings including service account tokens. Same handling as the desktop config.

### Directory Structure on NFS

```
/mnt/storage/claudebox/claude-backup/
├── latest/             # Always current state (rsync)
└── snapshots/
    └── YYYY-MM-DD/     # Dated snapshots, pruned after 90 days
```

The `latest/` directory is the fast-restore path — if you just need to recover the current state, copy from there. The dated snapshots are for "I need Tuesday's memory database, not today's."

### Secrets Handling

The desktop config and extension settings contain live tokens. A sanitized template of the desktop config exists in the repo at `configs/claude-desktop/claude_desktop_config.json`, but the real files are NFS-only and excluded from any git repository.

## Docker Stack Backup

The third backup layer handles Docker container appdata. The script (`scripts/docker-stack-backup.sh`) is a PM2 cron job that runs nightly, discovers all Compose stacks with appdata bind mounts, stops each stack, archives the appdata + compose file, and restarts the containers.

| Setting | Value |
|---------|-------|
| Script | [`scripts/docker-stack-backup.sh`](../../scripts/docker-stack-backup.sh) |
| Schedule | Daily at 1:00 AM (PM2 cron) |
| Destination | `/mnt/storage/claudebox/docker-backups/` (NFS) |
| Notifications | ntfy, Pushover, or email (configurable) |

### How It Works

The script auto-discovers stacks by scanning the compose directory for subdirectories containing a `compose.yaml` (or `docker-compose.yml`). For each stack that has bind mounts pointing to the appdata directory:

1. Records which containers are currently running
2. Stops the stack (`docker compose down`)
3. Archives the compose file, `.env`, and the appdata directory into a single tarball
4. Restarts only the containers that were running before (not the whole stack)
5. If restart fails, retries up to 3 times with a delay, then sends a critical alert

Stacks without appdata mounts are skipped automatically. The script supports dry-run mode (`--dry-run`) which shows what would be backed up, estimated sizes, and available disk space without touching anything.

### Configuration

The script has a configuration section at the top with all the paths and options:

```bash
STACK_BASE="$HOME/docker"                # Directory containing stack subdirs
APPDATA_PATH="/opt/appdata"              # Bind mount root for stack appdata
BACKUP_DEST="/mnt/backup/docker-backups" # Where backups land (NFS mount recommended)
```

Compression is configurable (gzip, bzip2, xz, zstd, or none) with optional parallel compression support. If your storage backend already handles compression (like ZFS with LZ4), set compression to `none` to avoid double-compressing.

### Notifications

The script supports three notification methods, all independently toggleable:

- **ntfy** — Self-hosted push notifications. Needs a server URL and topic.
- **Pushover** — Push notifications via the Pushover service. Needs user key and API token.
- **Email** — Via sendmail or direct SMTP. Supports TLS.

On success, a summary is sent with counts of backed-up, skipped, and failed stacks. On failure, an error summary goes out. If a stack fails to restart after backup, a separate critical-priority alert fires immediately — don't ignore these.

### Standalone Value

The docker-stack-backup script is independently useful outside this stack. It's a fork of [TadMSTR/docker-stack-backup](https://github.com/TadMSTR/docker-stack-backup) and works with any Docker Compose setup that uses bind mounts for persistent data. Drop it on any host, configure the three paths, and schedule it.

## What's Not Backed Up

Worth being explicit about what falls outside the backup scope:

- **Docker images** — Not backed up. They're pulled from registries on rebuild. Only the compose files and appdata matter.
- **NFS mount contents** — The NFS share is the backup *target*, not a backup *source*. If the storage server fails, backups are gone. Offsite replication is a future enhancement.
- **Temporary Claude artifacts** — `vm_bundles`, `claude-code`, `Cache`, `Code Cache` directories are excluded from Backrest. These are large, ephemeral, and recreated on launch.
- **Browser and app caches** — Thorium, Discord, VSCodium, Librewolf caches are all excluded. No recovery value.

## Gotchas and Lessons Learned

**Backrest needs the NFS mount as a systemd dependency.** Without `Requires=mnt-storage-claudebox.mount` in the service file, Backrest will start before the NFS share is available and restic will fail trying to open a repo that doesn't exist yet. The error message isn't obvious — it looks like repo corruption, not a missing mount.

**Claude's `.gvfs` and `thinclient_drives` will break restic.** These are FUSE virtual mounts from GNOME/RDP sessions. Root can't read them, and restic will error out if it tries. Add them to excludes early.

**The docker-stack-backup restart logic matters.** The script only restarts containers that were running *before* the backup, not everything in the compose file. This prevents accidentally starting services that were intentionally stopped. The retry logic (3 attempts with delay) handles the occasional Docker daemon hiccup after rapid stop/start cycles.

**The Claude backup script exists because of a scope gap.** Backrest covers `/home/ted` which includes `~/.config/Claude/`, so technically the data is covered. But the rsync + dated snapshot approach gives you a simpler, faster restore path for just the Claude data. You could drop the custom script and rely solely on Backrest — the trade-off is convenience versus one more moving part.

**Test restores.** Having backups is half the job. Periodically verify you can actually restore from each mechanism: `restic restore` from a Backrest snapshot, copy from the `latest/` directory in the Claude backup, and extract a docker-stack-backup tarball. The docker-stack-backup repo includes a companion `docker-stack-restore.sh` script for guided restores.
