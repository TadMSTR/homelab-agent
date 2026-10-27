# docker-stack-backup

docker-stack-backup is a set of Bash scripts that back up Docker Compose stacks every night.
For each stack whose compose file binds a directory under the appdata root, it stops the
stack, captures the stack's appdata directory with its compose file and `.env`, and starts the
stack again. The capture can be a tar archive, a restic snapshot, or both. Each run writes a
machine-readable result (`status.json` plus an optional Prometheus textfile), so a failed
stack, a stale backup, or data outside the backup shows up as an alert, not only as a
log line. Restores go through an interactive wizard.

Root work goes through small root-owned helper scripts that take no paths from their caller.
The main script runs as an ordinary user.

- **Version:** v0.8.0 deployed (upstream also has v0.8.1, which changes only the host
  restore drill)
- **Repo:** `TadMSTR/docker-stack-backup` (public). The reference host runs a vendored copy
  in its scripts repo
- **Schedule:** nightly backup at 02:00, retention cleanup at 03:30 (system crontab, both
  wrapped for Healthchecks liveness)
- **Port:** none. It writes files to the backup share and the textfile directory

## Port / endpoint

There are no network listeners. Outputs:

| Path | What |
|------|------|
| `$BACKUP_DEST/<host>/<timestamp>/` | One run directory: a tar archive per stack (0600; run dirs 0700) |
| `$BACKUP_DEST/<host>/status.json` | Result of the latest run, written on success and on every abort path |
| `$BACKUP_DEST/<host>/<timestamp>/status.json` | Copy kept with the run, as history |
| `$PROM_TEXTFILE_DIR/docker_stack_backup.prom` | The same points as Prometheus gauges (`dsb_*`), if enabled |
| restic repository | One snapshot per stack per run, tagged `dsb`, `stack:<name>`, `kind:<daily\|full>`, `run:<ts>` |

## How a run works

1. **Discover stacks.** It reads every compose directory under the stack base. A stack is
   selected if its compose file references `$APPDATA_PATH`. The bind mount *is* the selector.
   Stacks without one are skipped as `no-appdata-reference`.
2. **Classify coverage.** Every stack's mounts (`docker compose config --format json`), skipped
   and stopped stacks included, are classified as archived, other-stack-appdata, stack-dir,
   system, input-ro, uncovered, named-volume, or tmpfs. Appdata directories that match no
   stack are listed as unowned. Coverage only reports; it never changes what gets backed up.
3. **Per stack:** stop the stack, then either take a read-only filesystem snapshot or archive
   directly. Start the stack again, archive from the snapshot, and delete the snapshot.
   Stopped stacks are archived live. Stacks are stopped and started, not torn down with
   `compose down`/`up`, so the backup never recreates containers or pulls images.
4. **Write the result**: `status.json`, the `.prom` file, the notification, and the liveness
   ping.

### Backup tiers (`x-backup`)

A stack can narrow its own backup in a top-level `x-backup:` block in its compose file:

```yaml
x-backup:
  exclude:                 # never backed up
    - path: ollama/models/blobs
      reason: "models re-pull from manifests"
  weekly:                  # only on the full (weekly) run
    - path: some/rebuildable/index
      reason: "rebuilt by <cmd>; a week's loss is acceptable"
  retention:               # restic retention for this stack, key by key
    daily: 7
    weekly: 4
    monthly: 1
```

- A stack with no declaration is backed up daily and in full. A declaration can only narrow
  a backup, and every entry needs a reason.
- Paths are literal and relative to the stack's appdata directory: no globs, no `..`, no
  leading `/`. They are excluded *anchored*, so `a/b` does not also drop `x/a/b`.
- **An invalid block is ignored as a whole.** The stack is backed up in full and reported as
  `config-error`, so a bad declaration never shrinks a backup.
- Good candidates are re-downloadable or rebuildable data, such as model blobs and package
  caches. Keep anything you cannot regenerate on the daily tier.
- `retention` overrides the host defaults key by key. A missing key takes the host default,
  so write every key you mean.

The run kind is `full` on `FULL_RUN_DAY` (default Sunday) or with `--full`, and `daily`
otherwise.

### Snapshot-assisted backup

With `SNAPSHOT_BACKEND=btrfs` (or `zfs`, or `auto`), each running stack is stopped, given a
read-only snapshot, and started again. The archive is then written from the snapshot. Downtime
becomes stop + snapshot + start rather than the time it takes to write the archive, which for
a large stack was minutes. The archive layout is unchanged, so restore, verify, and cleanup do
not care which path made it.

A btrfs snapshot does not descend into nested subvolumes, and a ZFS snapshot excludes child
datasets. A nested subvolume, child dataset, mountpoint, or unreadable directory under a stack
therefore sends that stack back to plain stop-archive-start, with a `fallback_reason`. Any
snapshot failure falls back the same way, and a stack is never stopped twice. Leftover
snapshots are swept at the start of each run. A snapshot that cannot be deleted is counted and
named in the notification, because a leftover snapshot pins disk.

Setting the backend explicitly (`btrfs`) makes a broken snapshot setup fail the preflight
instead of quietly falling back.

### Backends: tar and restic

`BACKENDS=tar|restic|"tar restic"`. Both backends read the same source (the snapshot, or the
live directory while the stack is stopped), so a stack is stopped once whatever the number of
backends. They exclude exactly the same files.

- **restic** keeps one deduplicated snapshot per stack. `forget` applies per-stack retention
  after each backup (default 7 daily / 4 weekly / 6 monthly). `prune` and a rotating
  `check --read-data-subset` run on the full run. restic never runs as root. A dedicated user
  holds only `CAP_DAC_READ_SEARCH` and gets the repository password on stdin, never in argv
  or the environment. The helper refuses retention counts below its floors, so a caller
  cannot erase history through the grant.
- **`TAR_SCHEDULE=full`** writes the tar set only on the weekly full run. That set is a copy
  that depends on neither the restic repository nor its password. Pair it with cleanup
  `RETENTION_DAYS=27 KEEP_MIN=4` to keep four weekly sets.

The reference host is running a **restic trial**: `BACKENDS="tar restic"` with
`TAR_SCHEDULE=daily`, so both backends run every night. Once the trial is done, tar moves to
weekly. The restic repository is separate from the one Backrest uses.

### Services that must not be stopped

The nightly cycle stops every selected stack. A service that seals itself or loses state on
stop should keep its state **outside the stop-and-tar path**, meaning not bind-mounted from
the appdata root, and should be backed up by its own native mechanism. A secrets store such as
OpenBao or Vault is the usual case: a stop seals it, and it stays sealed until someone
unseals it. The reference host keeps OpenBao's Raft storage outside the appdata tree. A
separate daily job streams a Raft snapshot to the backup share, verifies it, and prunes old
ones. The mount is listed in the coverage exemptions with that reason.

## Configuration

`config.sh` sits next to the scripts. It is sourced, so keep secrets out of it if it is
tracked in git. The keys that matter:

| Key | Example | Purpose |
|-----|---------|---------|
| `DOCKHAND_BASE` / `DOCKHAND_APPEND_HOSTNAME` | `~/docker` / `false` | Stack base; `false` for a flat single-host layout |
| `APPDATA_PATH` | `/srv/appdata` | Appdata root; also the stack selector |
| `BACKUP_DEST` | `/mnt/nas/backups/docker-backups` | Share for archives and `status.json` |
| `EXCLUDE_PATTERNS` | `("nextcloud/clamav")` | Global, unanchored tar excludes |
| `ELEVATION_CMD` / `ELEVATION_HELPER_PATH` | `sudo` / `/usr/local/sbin/docker-backup-tar-create.sh` | Root tar helper |
| `SNAPSHOT_BACKEND` / `SNAPSHOT_HELPER_PATH` | `btrfs` / `…/docker-backup-snapshot.sh` | Snapshot-assisted backup |
| `BACKENDS` / `RESTIC_HELPER_PATH` / `TAR_SCHEDULE` | `"tar restic"` / `…/docker-backup-restic.sh` / `daily` | Backends |
| `RESTIC_KEEP_DAILY/WEEKLY/MONTHLY` | `7` / `4` / `6` | Host-default restic retention |
| `FULL_RUN_DAY` | `7` | Day of week for the full run |
| `PLATFORM` | `auto` | `debian` / `truenas` defaults for elevation and snapshots |
| `LOCK_FILE` | `~/run/docker-stack-backup.lock` | Single-run lock; a symlink is refused |
| `PROM_TEXTFILE_DIR` | `<appdata>/observability/alloy/textfile` | Enables the `.prom` output |
| `PING_URL` | `""` | Built-in Healthchecks-style ping. The reference host uses a cron wrapper instead, so no ping key is committed |
| `MATRIX_ENABLED` / `NTFY_ENABLED` | `true` | Notifications |

**Root helpers.** There are three: tar, snapshot, and restic. Each is root-owned (0750) in
`/usr/local/sbin`, and all three are covered by one `NOPASSWD` sudoers line. Root-set
constants inside each helper decide every path: the appdata root, the snapshot directory, the
restic binary, the repository, the password file, and the run-as user. None of these are
`config.sh` keys, because `config.sh` can be written by the backup user. The appdata root must
contain no symlink, or the restic helper refuses every backup.

**Coverage exemptions.** `coverage-exemptions.conf` sits next to the script, one
`<kind>|<subject>|<reason>` entry per line. Use it for writable host paths that are backed up
some other way, such as a Backrest plan, a native snapshot job, or a git remote. Every entry
needs a reason, and an entry that matches nothing is reported stale. The file is read as data
and never sourced. Track it in git: every exemption silences part of the "uncovered" alert, so
a change should go through review.

## Dependencies

- **Docker Compose** and the compose tree; **Dockhand's** stack layout (`DOCKHAND_BASE`)
- **Backup share**, typically an NFS mount from a NAS. Restore and verify read it as its owner,
  so they also work on a root-squashed export
- **btrfs or ZFS** for snapshot-assisted backup (optional); **restic ≥ 0.17.1** for the restic
  backend (optional)
- **Monitoring** (optional): Grafana Alloy mounts the textfile directory read-only and runs a
  textfile-only exporter; Prometheus scrapes it; Grafana holds the alert rules. Healthchecks
  watches both cron jobs, and the Healthchecks sync job reads the backup's system crontab so
  the checks stay in step with it

What depends on it: every stack with state under the appdata root. Component docs for those
stacks refer here for their backup story.

## Operations

```bash
# What would happen tonight: run kind, tiers with reasons, snapshot plan per stack
./docker-stack-backup.sh --dry-run

# Coverage classifier JSON for every stack (read-only; stops and writes nothing)
./docker-stack-backup.sh --coverage-report

# Force a full run (weekly-tier paths included)
./docker-stack-backup.sh --full

# Back up selected stacks interactively (applies exclude tiers; no snapshots)
./docker-stack-backup-manual.sh

# Restore: pick tar or restic (Step 0), a stack, and a run; preview, safety copy, replace
sudo ./docker-stack-restore.sh

# Verify archives
./backup-verify.sh --list
./backup-verify.sh --stats

# Last result
jq '{outcome, coverage: .coverage.status, stacks: [.stacks[] | {name, result, reason}]}' \
  "$BACKUP_DEST/$(hostname)/status.json"
```

Logs go to the script's own log file and to the cron log. Every failure has a `reason` in
`status.json`. Reasons are a documented contract: `stop-failed`, `archive-failed`,
`restart-failed`, `running-state-mismatch`, `restic-backup-failed`, `restic-repo-locked`,
`restic-password-wrong`, and others.

A restic restore streams the helper's `dump` into the same wizard steps as a tar restore. One
difference: hard links inside appdata come back as separate files.

### Alerts worth having

Rules on the `.prom` gauges in the reference deployment:

| Fires when | Notes |
|------------|-------|
| No successful run in 26 h, or the series is gone | NoData must alert. Seed a `.prom` with the exact HELP text before the first run, or the rule fires immediately |
| Any stack failed, or the run aborted | |
| A run found zero stacks | Catches a moved stack base |
| Uncovered items, stale exemptions, or x-backup config errors | Aggregate every term with `sum by (host)` |
| The textfile collector cannot read the directory, or it holds anything other than the one `.prom` file | A planted second `.prom` could mask the others |

Lock the scrape job down. Do not set `honor_labels`. Keep only `dsb_.*|node_textfile_.*`, use
a label allowlist, and add a charset guard on free-text labels. Otherwise anyone who can write
the textfile directory can inject series into other jobs. A separate hourly guard script that
lists the directory outside the Prometheus path covers the case where a planted file
redeclares the collector's own metrics.

The restic backend adds rules for an unusable repository, stale or failed `forget`/`prune`/
`check`, a stale backend, and a restore not verified for over 35 days. The last one comes from
the host restore drill, which records `restore-verified.json`.

## scoped-mcp integration

None. docker-stack-backup is a cron job, not an MCP server, and no agent invokes it through
scoped-mcp. Agents running as the backup user can drive the root helpers' sudoers grant. That
is why the helpers take no caller-supplied paths, refuse symlinks and swapped directories,
and enforce retention floors.

## Version history

| Version | Highlights |
|---------|-----------|
| 0.8.1 | Host restore drill fixes only |
| 0.8.0 | restic backend, `TAR_SCHEDULE`, per-stack retention with floors, restic restore through the wizard, owner-only archives (0600/0700), restore-verified metric |
| 0.7.0 | `x-backup` tiers, run kind (daily/full), snapshot-assisted backup (btrfs/ZFS), platform profiles; tar helper no longer reads the caller's temp dir as root |
| 0.6.0 | `status.json`, Prometheus textfile, coverage classifier and exemptions, liveness ping, safe INT/TERM handling, `--coverage-report` |
| 0.5.x | Stop/start instead of `compose down`/`up`; restore wizard fixes; `KEEP_MIN` in cleanup |

## Related Docs

- [backrest.md](backrest.md): restic plans for host paths outside the appdata tree
- [btrbk-daily.md](btrbk-daily.md): Btrfs snapshot scheduling
- [grafana-alloy.md](../observability/grafana-alloy.md): textfile exporter host
- [healthchecks.md](../observability/healthchecks.md): cron liveness
- [appdata-layout.md](../../operations/appdata-layout.md): the appdata tree this backs up
- Upstream docs: `USAGE.md`, `STATUS.md`, `RESTIC.md`, `ELEVATION.md`, `SECURITY.md` in
  `TadMSTR/docker-stack-backup`
