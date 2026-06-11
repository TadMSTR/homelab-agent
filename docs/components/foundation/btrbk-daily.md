# btrbk-daily

Scheduled job that runs btrbk for automated daily Btrfs timeline snapshots.
Covers @rootfs, @opt, and @home subvolumes with 7-day / 4-week / 3-month retention.

- **Script:** `~/scripts/btrbk-daily.sh`
- **Interpreter:** `bash`
- **Schedule:** PM2 cron, daily at 03:00 (`0 3 * * *`)
- **Log:** `~/logs/btrbk-daily.log`
- **No listening port** — runs as a batch job

## How It Works

1. Runs `sudo btrbk run`, logging output to `~/logs/btrbk-daily.log`
2. On success — logs completion, exits
3. On failure — sends a Matrix alert to `#agents` via `send-matrix.sh`, exits 1

Snapshot retention is configured in `/etc/btrbk/btrbk.conf` (managed by btrbk).

## Configuration

| Setting | Value |
|---------|-------|
| btrbk config | `/etc/btrbk/btrbk.conf` |
| Subvolumes | @rootfs, @opt, @home |
| Retention | 7 daily, 4 weekly, 3 monthly |
| Log file | `~/logs/btrbk-daily.log` |
| Alert script | `~/scripts/send-matrix.sh` |
| Alert room | `#agents` |

## Dependencies

- **btrbk** — Btrfs snapshot manager (installed system-wide)
- **sudo** — required for btrbk run
- **send-matrix.sh** — Matrix alerting on failure

## Operations

```bash
# Check last run
pm2 show btrbk-daily

# View logs
tail -20 ~/logs/btrbk-daily.log

# Trigger manual snapshot
pm2 restart btrbk-daily

# List current snapshots
sudo btrbk list
```

## Related Docs

- [btrfs-scrub-monthly.md](btrfs-scrub-monthly.md) — monthly integrity scrub
- [snapshot-space-probe.md](../platform/snapshot-space-probe.md) — snapshot disk usage monitoring
