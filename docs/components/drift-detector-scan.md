# drift-detector-scan

drift-detector-scan is a PM2 cron job that detects infrastructure drift in build
artifacts. It scans recent build close-out notes and verifies that expected audit
reports exist, logging warnings when they are missing.

- **PM2 ID:** 22
- **Schedule:** Every 15 minutes (`*/15 * * * *`)
- **Script:** `/home/ted/scripts/drift-detector-scan.sh`
- **Mode:** cron-restart, fork

## How It Works

1. Scans build close-out notes from the last 15-minute window in `~/.claude/memory/shared/`
2. Extracts build names from recent entries
3. Verifies audit reports exist at `~/.claude/comms/artifacts/audit-reports/<build>/`
4. Logs `DRIFT` warnings for builds missing audit reports (non-exempt builds only)

## Dependencies

- Memory system (`~/.claude/memory/shared/`)
- Audit report directory (`~/.claude/comms/artifacts/audit-reports/`)

## Alerting

File-based logging to `~/logs/`. No Matrix integration.

## Operations

```bash
pm2 logs drift-detector-scan --lines 50   # Recent output
pm2 restart drift-detector-scan            # Force immediate run
```
