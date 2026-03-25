# claudebox-deploy

When the hardware dies, or when I want to stand up a second instance to test something, I need to be able to rebuild Claudebox from scratch without spending a day manually reinstalling tools and reconfiguring everything. That's what this script is for.

`claudebox-deploy` is a single bash script (~800 lines) that provisions a fresh Debian/Ubuntu machine into a working Claudebox — packages, Docker, PM2, MCP servers, SSH keys, NFS mounts, all repos, and optionally the full Claude state from an NFS backup. It's not a configuration management system and it doesn't pretend to be. It's an automation layer over the same steps I'd run by hand, written down so I don't have to remember them.

## Architecture layer

This is a Layer 1 concern — it builds the host that everything else runs on. The script runs once (or whenever you need to reprovision) and produces the environment that Claude Desktop, the MCP servers, and the Claude Code engine all depend on. It's not a persistent service — it's a setup tool.

The script has a hard dependency on the NFS backup volume. Almost everything it restores — SSH keys, Docker state, Claude config, memory snapshots — lives on that share. If the NFS server isn't reachable, the script halts.

## What it deploys

Running the script covers these areas in order:

- **System packages** — git, curl, Node 20, Python 3, Docker CE, nfs-common
- **Docker setup** — Docker CE from official repos, creates the `claudebox-net` bridge network
- **Docker state** — restores compose files, `.env` files, and appdata from NFS backup
- **PM2** — installs PM2 globally, configures systemd startup, restores the saved process list
- **Claude Code tooling** — bubblewrap, `settings.json` with deny rules, memsearch with local embeddings
- **qmd** — installs the semantic search service, patches the MCP client config, initializes collections
- **CUI** — Claude Code web UI setup
- **SSH keys** — restores keys from NFS and configures host aliases for multiple GitHub identities
- **uv** — Python package manager, used by several MCP servers
- **Netdata** — agent monitoring, edge channel
- **Claude Desktop** — installs from `.deb` on the NFS share, deploys `claude_desktop_config.json` with secrets
- **Memory state** — fresh start or restore from backup (your choice at runtime)
- **NFS fstab entries** — makes mounts persistent across reboots
- **Repos** — clones all repos listed in `repos-manifest.tsv`

## Prerequisites

Before running the script, the NFS server must be set up with this layout (paths are illustrative — configure to match your environment):

```
/mnt/nfs/claudebox/
├── ssh/                    # SSH private/public keys
├── claude-backup/
│   └── latest/             # Written by backup-claude.sh nightly
│       ├── claude_desktop_config.json
│       ├── basic-memory/
│       └── ...
├── docker/                 # Compose files + .env files
├── appdata/                # Docker appdata archives
└── packages/
    └── claude-desktop.deb  # Claude Desktop installer
```

The machine itself needs:
- Debian 12+ or Ubuntu 22.04+
- Two NICs: one on the LAN (`192.168.x.x`) and one on the storage network (`10.10.x.x`) — required for NFS to work without going through the main router
- Sudo access for the deploy user

## Configuration

### repos-manifest.tsv

All repos are tracked in a tab-separated manifest:

```tsv
repos/personal/my-repo	git@github-personal:myuser/my-repo.git
repos/work/work-project	git@github-work:workuser/work-project.git
```

The first column is the destination path relative to `$HOME`. The second is the remote URL. SSH host aliases (`github-personal`, `github-work`) map to different keys in `~/.ssh/config` — the deploy script writes those aliases out from the keys it restores.

Keep this file up to date as you add or remove repos. There's an `update-repos-manifest.sh` helper that can regenerate it from your current checkouts.

### Memory mode

At runtime the script asks whether to start fresh or restore from backup:

```
Memory mode:
  1) fresh  — start with empty memory (new instance)
  2) clone  — restore memory snapshot from NFS (rebuild of existing machine)
```

Fresh mode is for bringing up a second instance or starting over. Clone mode is for disaster recovery — it pulls the `latest/` snapshot from the NFS backup and puts everything back where Claude expects it.

## Integration points

The deploy script is on the receiving end of the backup chain described in [backups.md](./backups.md). The nightly `backup-claude.sh` job writes to the `latest/` directory on NFS — that's exactly what `claudebox-deploy` restores from. If you rebuild and the backup is recent, you pick up almost exactly where you left off.

After a successful deploy, the environment is ready for:
- Claude Desktop with all MCP servers configured
- Docker stacks to be started (`docker compose up -d`)
- PM2 to start its managed processes (`pm2 resurrect`)
- System cron jobs active (`/etc/cron.d/` entries restored from NFS backup)
- Claude Code sessions scoped to any project

The script doesn't start Docker containers or PM2 processes — it restores the configs and saved state, then leaves you to bring services up. That's intentional: after a restore you want to verify things look right before starting everything.

## Gotchas

**`claude_desktop_config.json` contains live secrets.** API tokens for every MCP server are in this file. The deploy script pulls it from NFS — it should never be committed to any git repo. The NFS share is the source of truth for this file.

**NFS must be reachable at deploy time.** The script mounts NFS early and halts if it can't connect. If you're deploying on a machine that hasn't been added to the NFS export list, do that first.

**Dual NIC is a real requirement.** If you only have one interface, the storage network check will fail. I went this route to keep backup traffic off the main LAN, but it does mean a single-NIC VM won't work as a drop-in replacement without modifying the script.

**PM2 process restoration depends on a saved dump.** `pm2 resurrect` requires an existing saved state on NFS. If you're running fresh (no prior backup), you'll need to start PM2-managed processes manually and run `pm2 save` before the backup job has a chance to snapshot them.

**System cron jobs need a prior backup to restore.** `/etc/cron.d/` entries (including `docker-stack-backup`) are restored from the NFS backup written by `backup-claude.sh`. On a first-time deploy with no prior backup, these entries won't exist and you'll need to create them manually. The deploy script logs a warning with the expected cron line if the backup is missing.

**The repos manifest drifts.** If you add a repo and forget to run `update-repos-manifest.sh`, a future deploy won't clone it. Make updating the manifest part of your workflow when adding new repos.

## Standalone value

You don't need the rest of the homelab-agent stack to use this pattern. If you have any machine you rebuild occasionally and want to automate the provisioning, the core idea — an idempotent bash script that pulls state from NFS — applies broadly. The Claude-specific pieces (Desktop config, memory restore, MCP server setup) are just sections of a larger script. Strip those out and you have a general-purpose machine provisioner.

The repos manifest pattern in particular is worth borrowing. A simple TSV file that maps local paths to remotes, with a helper script to regenerate it — that's 20 lines of tooling that pays off every time you rebuild.
