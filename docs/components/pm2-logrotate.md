# pm2-logrotate

pm2-logrotate is a PM2 module that handles automatic log rotation for all PM2-managed processes on claudebox. Without it, PM2 appends to log files indefinitely — long-running services accumulate logs until the disk fills or manual cleanup is needed. pm2-logrotate runs as a sidecar module inside the PM2 daemon and rotates logs nightly.

It sits in [Layer 1](../../README.md#layer-1--host--core-tooling) as foundational host tooling. Every PM2 process on claudebox — agents, MCP servers, cron jobs, pipelines — relies on it to keep log files bounded.

- **Module version:** 3.0.0
- **PM2 module path:** `~/.pm2/modules/pm2-logrotate/`
- **PM2 process id:** 0

## What It Does

pm2-logrotate hooks into the PM2 module system and runs a worker loop (every 30 seconds) that checks each log file's size. At midnight UTC it rotates all logs regardless of size, appending a timestamp suffix and optionally compressing the old file. PM2 continues writing to the original log path — the module handles renaming transparently.

**Current configuration:**

| Setting | Value | Notes |
|---------|-------|-------|
| `rotateInterval` | `0 0 * * *` | Daily at midnight UTC |
| `workerInterval` | `30` (seconds) | Size-check polling interval |
| `max_size` | `10M` | Rotates early if a file exceeds this before midnight |
| `retain` | `7` | Number of rotated files to keep per log path |
| `compress` | `true` | Gzip-compress rotated files |
| `dateFormat` | `YYYY-MM-DD_HH-mm-ss` | Suffix appended to rotated filenames |
| `rotateModule` | `true` | Rotate pm2-logrotate's own logs too |

At the time of writing: 256 files tracked, 39.31 MB global logs size.

## Installation

pm2-logrotate is a PM2 module installed via:

```bash
pm2 install pm2-logrotate
```

Configuration is set with `pm2 set`:

```bash
pm2 set pm2-logrotate:retain 7
pm2 set pm2-logrotate:compress true
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
pm2 set pm2-logrotate:workerInterval 30
```

Settings persist in `~/.pm2/modules/pm2-logrotate/package.json` and survive `pm2 resurrect`.

## Log File Layout

Each PM2 service has two log files:

```
~/.pm2/logs/<service-name>-out.log    # stdout
~/.pm2/logs/<service-name>-error.log  # stderr
```

After rotation, the old file is moved to:

```
~/.pm2/logs/<service-name>-out__2025-01-15_00-00-00.log.gz
```

The `.log.gz` naming only applies when `compress: true`. The active file path is always the unadorned `<service>-out.log` — PM2's `get_logs` tool and `pm2 logs` command always read the current file.

## Integration Points

**All PM2 services.** pm2-logrotate applies to every process PM2 manages, including [pm2-mcp](pm2-mcp.md), [task-dispatcher](task-dispatcher.md), [memory-pipeline](memory-pipeline.md), and all cron jobs. No per-service opt-in is needed.

**Monitoring.** The module exposes heap and event loop metrics to PM2's internal metrics system. These appear in `pm2 monit` and `pm2 show pm2-logrotate` under "Code metrics value."

**Deploy script.** `claudebox-deploy.sh` includes `pm2 install pm2-logrotate` and the `pm2 set` configuration commands in the PM2 setup section. A fresh deploy automatically restores the module.

## Gotchas and Lessons Learned

**`retain` counts rotated files, not days.** With daily rotation, `retain: 7` keeps roughly 7 days of history. But if `max_size` triggers a mid-day rotation, you'll accumulate more than one file per day and hit the retain limit faster. At 10M/file and typical agent log volumes, mid-day rotation is uncommon.

**Module logs rotate themselves.** `rotateModule: true` means pm2-logrotate's own `pm2-logrotate-out.log` and `pm2-logrotate-error.log` are subject to the same rotation policy. If you're debugging the module, check for rotated versions if the current log file is sparse.

**After `pm2 kill`, reinstall the module.** `pm2 kill` shuts down the daemon and unregisters all processes — but the module configuration in `package.json` survives. After a kill + restart + `pm2 resurrect`, the module is not automatically reloaded. Run `pm2 install pm2-logrotate` again (it's idempotent).

**`max_size` is checked per worker interval, not continuously.** The 30-second worker poll means a file could temporarily exceed `max_size` between checks. In practice this is fine — the drift is seconds at most.

## Related Docs

- [pm2-mcp](pm2-mcp.md) — MCP server for structured PM2 access; its logs are managed by pm2-logrotate
- [task-dispatcher](task-dispatcher.md) — one of the higher-volume PM2 services that benefits from log rotation
- [claudebox-deploy](claudebox-deploy.md) — deploy script that installs and configures pm2-logrotate
