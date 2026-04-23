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
| CloudCLI | [cloudcli.md](cloudcli.md) | Claude Code web UI — file explorer, git integration, shell terminal, MCP management, WebSocket/SWAG proxy config |
| Agent Panel | [agent-panel.md](agent-panel.md) | Homelab operations panel — service health, PM2, Docker, file browser, diagnostics, Backrest; SWAG token injection auth model |
| jobsearch-mcp | [jobsearch-mcp.md](jobsearch-mcp.md) | Multi-board job search, resume scoring, application tracking — FastMCP server for LibreChat agents |
| Diag-Check | [diag-check.md](diag-check.md) | Scheduled lightweight diagnostics via agent panel API, failure alerting |
| Grafana (claudebox) | [grafana-claudebox.md](grafana-claudebox.md) | Local Grafana + InfluxDB for AI agent observability — separate from atlas infrastructure monitoring |
| Plane | [plane.md](plane.md) | Self-hosted project management — Helm platform tracking, 11-container stack, MCP integration, multi-path SWAG proxy |
| Helm Dashboard | [helm-dashboard.md](helm-dashboard.md) | CloudCLI plugin — monitoring tab for walk-away agent builds, eight panels, WebSocket live updates |
| ollama-queue-proxy | [ollama-queue-proxy.md](ollama-queue-proxy.md) | Smart pool manager for Ollama fleet — per-client auth, priority queuing, model-aware routing, Valkey embedding cache, client injection |

## Layer 3 — Multi-Agent Engine

| Component | Doc | What It Covers |
|-----------|-----|---------------|
| qmd | [qmd.md](qmd.md) | Semantic search, dual transport (stdio + HTTP), GPU acceleration, config |
| memsearch | [memsearch.md](memsearch.md) | Memory recall for Claude Code, plugin integration, config |
| Milvus | [memsearch.md](memsearch.md) (§Vector Store) | Milvus standalone vector database — backing store for memsearch and qmd indexes |
| Hister | [hister.md](hister.md) | Browser-based semantic + keyword search over memory corpus; preview shim, SWAG routing, auth model |
| memory-sync | [memory-sync.md](memory-sync.md) | Automated knowledge distillation pipeline, distillation rules, PM2 cron |
| Graphiti | [graphiti.md](graphiti.md) | Temporal knowledge graph — Neo4j, entity ontology, data flow, Graphiti MCP |
| graphiti-mcp | [graphiti-mcp.md](graphiti-mcp.md) | Graphiti MCP server container — quick reference, see graphiti.md for full docs |
| doc-health | [doc-health.md](doc-health.md) | Weekly documentation audit — drift, index, coverage, staleness, sanitization |
| AI Cost Tracking | [ai-cost-tracking.md](ai-cost-tracking.md) | Claude Code JSONL parsing, token/cost metrics, LibreChat Prometheus → InfluxDB → Grafana |
| Inter-Agent Communication | [inter-agent-communication.md](inter-agent-communication.md) | File-based handoff pattern, queue directories, status lifecycle, security audit workflow, stale monitoring |
| Agent Orchestration | [agent-orchestration.md](agent-orchestration.md) | Task queue, dispatcher, agent manifests, risk-based approval gates, task-approve CLI |
| NATS JetStream | [nats-jetstream.md](nats-jetstream.md) | Agent event bus — task lifecycle subjects, JetStream streams, NATS CLI, fire-and-forget design |
| n8n | [n8n.md](n8n.md) | Webhook workflow engine — visual task routing, risk-based approval gating, ntfy alerting, Postgres-backed |
| Security Agent | [security-agent.md](security-agent.md) | Post-build security audits, three-category triage, action plan routing, stale queue monitoring |
| Auto Mode | [auto-mode.md](auto-mode.md) | Claude Code permission classifier — settings.json environment rules, per-project SSH permissions, CloudCLI SDK patch |
| Temporal | [temporal.md](temporal.md) | Durable workflow engine — multi-phase build automation, 5-container stack, Postgres-backed state, gRPC API |
| scoped-mcp | [scoped-mcp.md](scoped-mcp.md) | Per-agent MCP tool proxy — manifest-driven module loading, resource scoping, credential isolation, audit logging |

## Layer 1 — Core Tooling

| Component | Doc | What It Covers |
|-----------|-----|---------------|
| homelab-ops MCP | [homelab-ops-mcp.md](homelab-ops-mcp.md) | FastMCP HTTP tool server — shell, files, processes; shared by Claude Code and LibreChat |
| pm2-mcp | [pm2-mcp.md](pm2-mcp.md) | Typed PM2 tool server — structured service health, log tail, restart/stop/start |
| ntfy-mcp | [ntfy-mcp.md](ntfy-mcp.md) | Push notification MCP server — `send_notification` tool call for Claude Code sessions |
| pm2-logrotate | [pm2-logrotate.md](pm2-logrotate.md) | PM2 log rotation module — daily rotation, 7-day retention, gzip compression |
| claudebox-deploy | [claudebox-deploy.md](claudebox-deploy.md) | Provisioning script — full machine rebuild from NFS backup, repo cloning, state restore |

## Cross-Cutting

| Component | Doc | What It Covers |
|-----------|-----|---------------|
| Backups | [backups.md](backups.md) | Backrest/restic, Claude backup, Docker appdata backup — schedules, retention, restore |
| Config Version Control | [config-version-control.md](config-version-control.md) | Gitea-backed git tracking for `~/docker/` and `/opt/appdata/`, nightly snapshot, Claude edit workflow |
