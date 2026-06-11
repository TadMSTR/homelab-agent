# btrfs-scrub-monthly

Monthly Btrfs integrity scrub across all mounted filesystems on forge. Detects silent
data corruption by verifying checksums against stored metadata.

- **Script:** `~/scripts/btrfs-scrub-monthly.sh`
- **Interpreter:** `bash`
- **Schedule:** PM2 cron, 1st of month at 02:00 (`0 2 1 * *`)
- **Log:** `~/logs/btrfs-scrub.log`
- **No listening port** — runs as a batch job

## How It Works

1. Iterates over mount points: `/`, `/opt`, `/home`, `/var`
2. Runs `sudo btrfs scrub start -B` (blocking) on each
3. Checks scrub status for each device — looks for `Error summary:` excluding `no errors found`
4. On errors — sends per-device Matrix alert to `#agents`
5. Logs final summary with error count

## Configuration

| Setting | Value |
|---------|-------|
| Devices | `/`, `/opt`, `/home`, `/var` |
| Log file | `~/logs/btrfs-scrub.log` |
| Alert script | `~/scripts/send-matrix.sh` |
| Alert room | `#agents` |

## Dependencies

- **btrfs-progs** — provides `btrfs scrub` command
- **sudo** — required for scrub operations
- **send-matrix.sh** — Matrix alerting on errors

## Operations

```bash
# Check last run
pm2 show btrfs-scrub-monthly

# View scrub log
tail -40 ~/logs/btrfs-scrub.log

# Trigger manual scrub
pm2 restart btrfs-scrub-monthly

# Check scrub status for root
sudo btrfs scrub status /
```

## Related Docs

- [btrbk-daily.md](btrbk-daily.md) — daily snapshot automation
- [snapshot-space-probe.md](../platform/snapshot-space-probe.md) — snapshot disk usage monitoring
