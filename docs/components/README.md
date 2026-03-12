# Component Docs

Per-component deep dives for each service in the homelab-agent stack. Each doc covers what the component does, why it's here, configuration details, integration points, and gotchas from running it in production.

For the architecture overview and how these components relate, see the [main README](../../README.md#architecture). For setup order, see [Getting Started](../getting-started.md).

## Layer 2 — Self-Hosted Services

| Component | Doc | What It Covers |
|-----------|-----|---------------|
| SWAG | [swag.md](swag.md) | Reverse proxy, wildcard SSL, Cloudflare DNS validation, proxy conf pattern |
| Authelia | [authelia.md](authelia.md) | SSO gateway, file-based user backend, SWAG integration |
| LibreChat | [librechat.md](librechat.md) | Multi-provider chat UI, web search pipeline, reranker wrapper, MCP integration |
| SearXNG | [searxng.md](searxng.md) | Private meta-search backend, Valkey cache, LibreChat web search |
| Dockhand | [dockhand.md](dockhand.md) | Docker stack manager, socket access, multi-host visibility |
| Open Notebook | [open-notebook.md](open-notebook.md) | AI research tool, SurrealDB, dual-port proxy config |
| CUI | *(doc pending)* | Claude Code web UI — headless agent monitoring, push notifications |
| CloudCLI | [cloudcli.md](cloudcli.md) | Claude Code web UI — file explorer, git integration, shell terminal, MCP management, WebSocket/SWAG proxy config |

## Layer 3 — Multi-Agent Engine

| Component | Doc | What It Covers |
|-----------|-----|---------------|
| qmd | [qmd.md](qmd.md) | Semantic search, dual transport (stdio + HTTP), GPU acceleration, config |
| memsearch | [memsearch.md](memsearch.md) | Memory recall for Claude Code, plugin integration, config |
| memory-sync | [memory-sync.md](memory-sync.md) | Automated knowledge distillation pipeline, distillation rules, PM2 cron |

## Cross-Cutting

| Component | Doc | What It Covers |
|-----------|-----|---------------|
| Backups | [backups.md](backups.md) | Backrest/restic, Claude Desktop backup, Docker appdata backup — schedules, retention, restore |
| Config Version Control | [config-version-control.md](config-version-control.md) | Gitea-backed git tracking for `~/docker/` and `/opt/appdata/`, nightly snapshot, Claude edit workflow |
