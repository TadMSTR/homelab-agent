# build-unblock-scan

build-unblock-scan is a PM2 cron job that monitors build plan dependencies and notifies
when previously blocked plans become unblocked. It enables the build pipeline to
progress without manual dependency checking.

- **PM2 ID:** 23
- **Schedule:** Every 30 minutes (`*/30 * * * *`)
- **Script:** `/home/ted/scripts/build-unblock-scan.sh`
- **Mode:** cron-restart, fork

## How It Works

1. Parses `~/.claude/comms/artifacts/build-plans/index.md` for plan completion status and dependencies
2. Identifies plans whose dependencies are now satisfied
3. Posts `[UNBLOCKED]` notifications to Matrix with a link to the build-plans index

## Dependencies

- Build plans index (`~/.claude/comms/artifacts/build-plans/index.md`)
- Matrix MCP server at `http://127.0.0.1:8487/mcp`

## Alerting

Posts to the Matrix `#forge` room with `[UNBLOCKED]` tag when plans become ready.

## Operations

```bash
pm2 logs build-unblock-scan --lines 50   # Recent output
pm2 restart build-unblock-scan            # Force immediate run
```
