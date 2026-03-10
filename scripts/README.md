# Scripts

Utility scripts for backup, monitoring, reindexing, and maintenance. Most are executed by PM2 cron jobs (see [`pm2/ecosystem.config.js.example`](../pm2/ecosystem.config.js.example)) but can be run standalone.

## Scripts

| Script | PM2 Job | What It Does |
|--------|---------|-------------|
| [docker-stack-backup.sh](docker-stack-backup.sh) | docker-stack-backup | Discovers Compose stacks, stops containers, archives appdata + compose files, restarts. Supports dry-run, configurable compression, retry logic, and notifications (ntfy, Pushover, email). |
| [memory-sync.sh](memory-sync.sh) | memory-sync | Runs Claude Code in headless mode to distill durable knowledge from agent memory and LibreChat conversations into the context repo. |
| [qmd-reindex.sh](qmd-reindex.sh) | qmd-reindex | Pulls latest from all configured git repos and re-runs `qmd index` to refresh the semantic search index. |
| [check-qmd-repos.sh](check-qmd-repos.sh) | qmd-repo-check | Scans the personal repos directory for repos not yet in the QMD index. Repos matching configured keywords (`claude`, `mcp`, etc.) are auto-added to `~/.config/qmd/index.yml` and a reindex is triggered. Everything else is reported via push notification for manual review. State is tracked so repeat notifications are suppressed until the unindexed set changes. |
| [check-resources.sh](check-resources.sh) | resource-monitor | Checks RAM, disk, Docker health, PM2 status, and NFS mount availability. Alerts via push notification if thresholds are exceeded. |
| [check-dep-updates.sh](check-dep-updates.sh) | dep-update-check | Checks npm global packages, pip packages, Docker images, and Claude Code for available updates. |

## Usage

All scripts are designed to run unattended but support manual execution:

```bash
# Dry-run a backup to see what would happen
./docker-stack-backup.sh --dry-run

# Manually trigger a reindex
./qmd-reindex.sh

# Check what repos are missing from the QMD index right now
./check-qmd-repos.sh

# Check system health now
./check-resources.sh
```

## Related Docs

- [PM2 ecosystem config](../pm2/ecosystem.config.js.example) — Scheduling and service definitions
- [Backups](../docs/components/backups.md) — Full backup strategy including these scripts
- [memory-sync](../docs/components/memory-sync.md) — Knowledge distillation pipeline details
- [qmd](../docs/components/qmd.md) — QMD index configuration and reindexing details
