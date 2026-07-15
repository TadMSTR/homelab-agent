# Platform — Monitoring Probes & Documentation Health

Background jobs that watch for drift, resource exhaustion, and documentation staleness. All run as PM2 cron processes and alert via Matrix when thresholds are crossed.

## Services

| Doc | Service | Schedule |
|-----|---------|----------|
| [doc-health.md](doc-health.md) | Documentation audit — weekly full scan + nightly targeted | Weekly / Nightly |
| [doc-sync-daily.md](doc-sync-daily.md) | Daily documentation sync | Daily |
| [writer-doc-queue.md](writer-doc-queue.md) | Processes doc-update-queue.jsonl via headless writer agent | Daily |
| [disk-space-probe.md](disk-space-probe.md) | Disk usage monitoring → Matrix alerts | Every 5 min |
| [snapshot-monitoring.md](snapshot-monitoring.md) | Btrfs capacity safety net + snapshot-bloat/drift trend + retention pruning | Every 15 min / Nightly |
| [drift-detector-scan.md](drift-detector-scan.md) | Configuration drift detection | Every 6 hours |
| [build-unblock-scan.md](build-unblock-scan.md) | Stalled build detection | Every 15 min |
| [git-drift-alert.md](git-drift-alert.md) | Uncommitted git change alerting | Every 6 hours |

## Alert Flow

All probes send alerts to Matrix rooms when issues are detected. Critical alerts (disk space, stalled builds) go to `#alerts`, informational drift reports go to the relevant agent room.
