# PM2 Services

PM2 manages both always-on daemons and scheduled cron jobs on the host. The ecosystem config defines everything in one file.

## Config

**[ecosystem.config.js.example](ecosystem.config.js.example)** — Copy to `ecosystem.config.js`, adjust paths and schedules to your environment, then `pm2 start ecosystem.config.js`.

---

## Always-On Daemons

| Service | Purpose |
|---------|---------|
| qmd | Semantic search HTTP endpoint — hybrid BM25 + vector + LLM reranking over repos, docs, and agent memory |
| homelab-ops-mcp | Shell, file, and process operations MCP server (port 8282) — Claude Code and LibreChat agents |
| pm2-mcp | PM2 process manager MCP server (port 8486, localhost only) — structured service access for Claude Code agents |
| ntfy-mcp | ntfy push notification MCP server (port 8484) — lets agents send push notifications natively |
| agent-bus | Inter-agent event bus FastMCP server — logs handoffs, audit requests, task failures to JSONL ledger and NATS JetStream |
| memsearch-watch | Re-indexes all memory directories within 5 seconds of any write — keeps semantic search current in real time |
| task-dispatcher | Routes submitted tasks between agents — auto-approves low-risk, gates medium/high via ntfy; runs every 2 minutes |
| cloudcli | Claude Code browser UI — file explorer, multi-session tabs, git integration, shell terminal (port 3004) |
| cui | Claude Code web UI — headless browser-based terminal sessions |
| agent-panel | Lightweight operations panel — PM2 services, Docker containers, diagnostics, file browser |

---

## Scheduled Jobs

| Service | Schedule | Purpose |
|---------|----------|---------|
| memory-promote-daily | 11:00 PM daily | Promotes same-day session transcripts to working-tier notes — context from the day's work is searchable the next morning |
| memory-pipeline | 4:00 AM daily | Orchestrator: runs memsearch-compact → qmd-reindex in sequence after nightly promotions |
| doc-sync-daily | 3:00 AM daily | Fetches official docs for all configured services, chunks them, writes to the memsearch-indexed doc cache |
| memory-sync-weekly | Mondays 7:00 AM | Promotes 14-day-old working notes to distilled tier, expires 90-day notes, runs graph entity dedup |
| librarian-weekly | Mondays 6:00 AM | Diffs memory and semantic search against the prime-directive repo; commits missing/updated skill files |
| docker-stack-backup | 1:00 AM daily | Stops containers, rsyncs appdata to NFS, restarts |
| doc-health-daily | 10:00 PM daily | Targeted doc scan on files touched that day — drift, index entries, sanitization |
| doc-health | Sundays 11:00 PM | Full weekly doc audit — drift, coverage, staleness, sanitization, structural integrity |
| resource-monitor | Every 6 hours | Checks RAM, disk, Docker containers, PM2 status, NFS mounts — alerts via ntfy |
| diag-check | Every 6 hours | Calls the agent panel's diagnostics API — ports, TLS expiry, DNS, cross-host ping |
| dep-update-check | Wednesdays noon | Checks for updates to pinned dependencies; alerts via ntfy |
| qmd-repo-check | 9:00 AM daily | Scans repos dir for collections missing from the QMD index; auto-adds keyword matches, notifies on others |
| qmd-issue-check | Mondays noon _(optional)_ | Checks tracked upstream GitHub issues for resolution; alerts via ntfy when fixed |

---

## Related Docs

- [Main README — PM2 Background Agents](../README.md#layer-3--multi-agent-claude-code-engine) — Architecture context
- [Scripts](../scripts/) — Scripts that PM2 cron jobs execute
- [homelab-ops-mcp](../docs/components/homelab-ops-mcp.md) — Shell and filesystem MCP server
- [pm2-mcp](../docs/components/pm2-mcp.md) — PM2 process manager MCP server
- [agent-bus](../docs/components/agent-bus.md) — Inter-agent event bus
- [memory-pipeline](../docs/components/memory-pipeline.md) — Memory promotion and indexing pipeline
- [doc-sync](../docs/components/doc-sync.md) — Documentation cache and sync
- [qmd](../docs/components/qmd.md) — Semantic search service
- [memory-sync](../docs/components/memory-sync.md) — Knowledge distillation pipeline
- [Backups](../docs/components/backups.md) — Docker appdata backup job details
