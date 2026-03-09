# PM2 Services

PM2 manages both always-on services and scheduled cron jobs on the host. The ecosystem config defines everything in one file.

## Config

**[ecosystem.config.js.example](ecosystem.config.js.example)** — Copy to `ecosystem.config.js`, adjust paths and schedules to your environment, then `pm2 start ecosystem.config.js`.

## Services

| Service | Type | Schedule | Purpose |
|---------|------|----------|---------|
| qmd | daemon | always-on | Semantic search HTTP endpoint for LibreChat and other clients |
| cui | daemon | always-on | Claude Code web UI |
| docker-stack-backup | cron | 1:00 AM daily | Container-safe appdata backup to NFS |
| memory-sync | cron | 4:00 AM daily | Knowledge distillation from agent memory |
| qmd-reindex | cron | 5:00 AM daily | Re-embed repos and docs for semantic search |
| resource-monitor | cron | every 6 hours | Health checks with push notifications |
| dep-update-check | cron | Wednesdays noon | Check for dependency updates |

## Related Docs

- [Main README — PM2 Background Agents](../README.md#layer-3--multi-agent-claude-code-engine) — Architecture context
- [Scripts](../scripts/) — The scripts that PM2 cron jobs execute
- [qmd](../docs/components/qmd.md) — Semantic search service config
- [memory-sync](../docs/components/memory-sync.md) — Knowledge distillation pipeline
- [Backups](../docs/components/backups.md) — Backup job details
