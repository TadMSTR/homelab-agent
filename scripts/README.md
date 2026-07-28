# Scripts

Maintenance and monitoring scripts for the homelab-agent platform. These run as PM2 processes or cron jobs on the forge host.

## Platform Maintenance

| Script | Purpose | How It Runs |
|--------|---------|-------------|
| `btrbk-daily.sh` | Btrfs snapshot creation (daily) | PM2 cron, daily |
| `btrfs-scrub-monthly.sh` | Btrfs filesystem scrub | PM2 cron, monthly |
| `build-unblock-scan.sh` | Scans for build blockers before agent sessions | On-demand / agent-triggered |
| `drift-detector-scan.sh` | Detects config drift between tracked repos and deployed state | PM2 cron, daily |
| `git-drift-alert.sh` | Alerts via Matrix when git repos have uncommitted changes | PM2 cron |
| `send-matrix.sh` | Send a message to a Matrix room | Utility, called by other scripts |
| `vault-seal-watcher.sh` | Monitors HashiCorp Vault seal status, alerts on seal | PM2 always-on |

## Monitoring

| Script | Purpose | How It Runs |
|--------|---------|-------------|
| `disk-space-probe.sh` | Pushes disk usage metrics to InfluxDB | PM2 cron, every 5 min |
| `doc-health.sh` | Checks documentation freshness and coverage | PM2 cron, daily |

`snapshot-space-probe.sh` was retired — it read `df` on `/.snapshots/`, which is
meaningless on forge's single-device Btrfs layout. Replaced by two purpose-built probes
(`snapshot-capacity-probe.sh`, `snapshot-bloat-probe.sh`) plus a retention pruner
(`snapshot-retention.sh`) — see
[snapshot-monitoring.md](../docs/components/platform/snapshot-monitoring.md) for the
full redesign.

## Memory Pipeline

| Script | Purpose | How It Runs |
|--------|---------|-------------|
| `memory-pipeline.sh` | Main memory processing pipeline (promote + sync) | PM2 always-on |
| `memory-promote-daily.sh` | Promotes working memory to distilled tier | PM2 cron, daily |
| `memory-sync-weekly.sh` | Syncs memory across tiers and to backup | PM2 cron, weekly |
| `memory-archive-mirror.sh` | Mirrors memory archives to NAS | PM2 cron |
| `memory-expire.py` | Expires aged working memory notes | PM2 cron |
| `memsearch-compact.sh` | Compacts memsearch index | PM2 cron |
| `memsearch-watch-fast.sh` | Polls for new memory files and indexes them (60s, working/session tiers) | PM2 always-on |
| `memsearch-watch-templates.sh` | Event-driven (`inotifywait`) indexing of template memory files | PM2 always-on |

## Documentation & Search

| Script | Purpose | How It Runs |
|--------|---------|-------------|
| `qmd-refresh.sh` | Reindexes the QMD semantic search corpus | PM2 cron, hourly |
| `doc-sync.py` | Syncs documentation from source repos to QMD | PM2 cron |

## Agent Infrastructure

| Script | Purpose | How It Runs |
|--------|---------|-------------|
| `task-dispatcher.py` | Routes incoming task queue entries to target agents | PM2 always-on |

`task-dispatcher.py` runs from `~/scripts/` on the live host and is **not mirrored in
this repo's `scripts/`** — an earlier copy checked into this repo had drifted from the
live script (wrong room targets, missing a `datetime` bugfix) and was deleted as a stale,
undeployed mirror. See [task-dispatcher.md](../docs/components/agent/task-dispatcher.md)
for the current, accurate description.

## What Was Removed from the Previous Version

The following claudebox-era scripts are not included because they have forge equivalents or were superseded:

| Removed | Replaced by |
|---------|-------------|
| `docker-stack-backup.sh` | Backrest (containerized backup service) |
| `memory-sync.sh` | `memory-pipeline.sh` + PM2 cron jobs |
| `trigger-proxy.py` | Removed — OAuth bridge replaced by Authentik outpost |
| `check-resources.sh` | Grafana dashboards + Telegraf metrics |
| `check-dep-updates.sh` | Renovate (containerized) |
| `qmd-reindex.sh` | `qmd-refresh.sh` |
| `git-snapshot.sh` | Backrest + btrbk snapshots |

## Environment

All scripts use `$HOME` for paths. Replace hostnames and IPs with your values:
- `<server-ip>` — your server's LAN IP
- `<nas-ip>` — your NAS or backup target IP
- `<lan-subnet>` — your LAN subnet in CIDR notation

The `send-matrix.sh` script requires `~/.secrets/matrix.env` with `MATRIX_URL`, `MATRIX_TOKEN`, and `MATRIX_ROOM_ID` set.
