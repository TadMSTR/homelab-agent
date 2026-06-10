# PM2 Services

PM2 manages the forge platform's always-on MCP servers and scheduled background jobs. All processes are defined in `ecosystem.config.js.example`.

## Usage

```bash
cp ecosystem.config.js.example ecosystem.config.js
# Edit paths if they differ from $HOME/repos/personal/ layout
pm2 start ecosystem.config.js
pm2 save
pm2 startup   # follow the printed command to enable boot start
```

## Process Categories

### Always-On MCP Servers

These run continuously and provide tool surfaces to agents via scoped-mcp:

| Process | Port | Purpose |
|---------|------|---------|
| `agent-bus` | 8488 | Inter-agent event log → NATS |
| `qmd` | 8181 | Semantic + keyword search over 9000+ docs |
| `memory-metadata-mcp` | 8490 | Structured queries over memory note metadata |
| `memory-search-mcp` | 8491 | Full-text search via OpenSearch |
| `memsearch-mcp` | 8493 | Hybrid vector+BM25+reranker memory search |
| `system-ops` | 8282 | Shell, file, and process operations |
| `patchmon-mcp` | 8484 | Apt package tracking and approval |
| `pm2-mcp` | 8486 | PM2 process management tool surface |
| `signoz-mcp` | 8492 | SigNoz APM queries |
| `matrix-mcp` | 8487 | Matrix messaging tool surface |
| `plane-mcp` | 8495 | Plane issue tracking |
| `code-server-mcp` | 8498 | VS Code server integration |

### Always-On Infrastructure

| Process | Purpose |
|---------|---------|
| `matrix-dispatcher` | Routes operator Matrix messages → agent project dirs |
| `matrix-admin-bot` | Matrix account provisioning |
| `matrix-task-queue-bot` | Task queue notifications via Matrix |
| `memsearch-watch-fast` | Polls for new memory files and indexes them |
| `memsearch-watch-templates` | Indexes template memory files |
| `memsearch-summarize` | Summarises raw session transcripts via Anthropic API |
| `memory-os-sync` | Syncs OS-level metrics to memory |
| `temporal-build-worker` | Temporal worker for autonomous build pipelines |
| `cloudcli` | CloudCLI web UI |
| `vault-seal-watcher` | Monitors Vault seal status (runs every 5 min via cron) |

### Scheduled Jobs

| Process | Schedule | Purpose |
|---------|----------|---------|
| `qmd-refresh` | Hourly | Reindexes the QMD doc corpus |
| `task-dispatcher` | Every 2 min | Routes task queue entries to agents |
| `drift-detector-scan` | Every 15 min | Checks config drift in tracked repos |
| `build-unblock-scan` | Every 30 min | Scans for build blockers |
| `git-drift-alert` | Every 30 min | Alerts on uncommitted repo changes |
| `agent-bus-cleanup` | Daily 03:50 | Prunes old agent-bus events |
| `agent-bus-reconcile` | Every 5 min | Reconciles NATS JetStream state |
| `doc-sync-daily` | Daily 03:00 | Syncs docs from source repos to QMD |
| `doc-health-daily` | Daily 22:00 | Checks documentation coverage |
| `writer-doc-queue` | Daily 21:00 | Processes pending doc queue entries |
| `memory-promote-daily` | Daily 23:00 | Promotes working → distilled memory |
| `memory-pipeline` | Daily 04:00 | Full memory processing pipeline |
| `memory-sync-weekly` | Mondays 07:00 | Cross-tier memory sync |
| `memory-archive-mirror` | Daily 02:30 | Mirrors memory to NAS |
| `memory-expire` | Daily 03:00 | Expires aged memory notes |
| `memsearch-compact` | Sundays 05:00 | Compacts memsearch index |
| `btrbk-daily` | Daily 03:00 | Btrfs snapshot creation |
| `btrfs-scrub-monthly` | 1st of month 02:00 | Btrfs filesystem scrub |
| `snapshot-space-probe` | Every 15 min | Snapshot space metrics → InfluxDB |
| `disk-space-probe` | Every 15 min | Disk space metrics → InfluxDB |
| `renovate-cron` | Hourly | Dependency update scanning |

## Useful Commands

```bash
# Status overview
pm2 status

# Interactive monitor
pm2 monit

# View logs for a process
pm2 logs <name> --lines 50

# Restart a process
pm2 restart <name>

# Reload all (graceful restart)
pm2 reload all
```

## Notes

- All scripts use `$HOME` for paths — adapt if your layout differs
- Scheduled jobs use `cron_restart` with `autorestart: false` — they run on schedule and stop
- Always-on services use `autorestart: true` — PM2 restarts them on crash
- The `vault-seal-watcher` is technically a scheduled job (every 5 min) but is classified as infrastructure because it alerts immediately
