# homelab-agent — Document Index

Machine-readable index for AI agents navigating this repo. Load only the sections relevant to your current task — don't load everything.

## Repo Map

```
homelab-agent/
├── README.md                          # Architecture overview, origin story, component guide
├── index.md                           # THIS FILE — agent navigation index
├── docs/
│   ├── architecture.md                # Detailed system architecture, data flows, network topology
│   ├── getting-started.md             # Setup order, prerequisites, stopping points
│   ├── decisions.md                   # Architecture decisions — major choices and the reasoning behind them
│   └── components/
│       ├── README.md                      # Component docs overview — layer table, component inventory
│       ├── swag.md                    # SWAG reverse proxy, Cloudflare DNS, proxy conf pattern
│       ├── authelia.md                # Authelia SSO, file-based user backend, SWAG integration
│       ├── librechat.md               # LibreChat setup, web search pipeline, reranker
│       ├── searxng.md                 # SearXNG + Valkey, search backend
│       ├── searxng-mcp.md             # SearXNG MCP server — FastMCP, ML reranking, Valkey cache, Crawl4AI integration
│       ├── crawl4ai.md                # Crawl4AI web scraper — JS-heavy page fetch fallback for searxng-mcp
│       ├── dockhand.md                # Dockhand Docker stack manager, socket access
│       ├── open-notebook.md           # Open Notebook AI research, SurrealDB, dual-port proxy
│       ├── cloudcli.md                # CloudCLI web UI — file explorer, git, shell, MCP management
│       ├── agent-panel.md             # Homelab operations panel — PM2, Docker, diagnostics, files
│       ├── agent-workspace-check.md   # Pre-edit workspace access resolver
│       ├── agent-workspace-scan.md    # Hourly workspace manifest validation + self-healing
│       ├── diag-check.md              # Scheduled diagnostics via agent panel API, failure alerts
│       ├── grafana-claudebox.md       # Local Grafana + InfluxDB for agent observability
│       ├── grafana-observability.md    # Loki, Alloy log shipping, image renderer
│       ├── qmd.md                     # qmd semantic search, dual transport, GPU acceleration
│       ├── memsearch.md               # memsearch memory recall for Claude Code sessions
│       ├── memory-sync.md             # Automated knowledge distillation pipeline
│       ├── graphiti.md                # Temporal knowledge graph — Neo4j, entity ontology, data flow
│       ├── graphiti-mcp.md            # Graphiti MCP server — Streamable HTTP, episode/node/fact tools
│       ├── doc-health.md              # Weekly doc audit — drift, coverage, staleness, sanitization
│       ├── ai-cost-tracking.md        # Claude Code JSONL → Telegraf → InfluxDB → Grafana cost metrics
│       ├── homelab-ops-mcp.md         # FastMCP HTTP tool server — shell, files, processes
│       ├── pm2-mcp.md                 # PM2 process manager MCP — list, logs, restart/stop/start
│       ├── ntfy-mcp.md                # Push notification MCP server — send_notification tool for Claude Code
│       ├── pm2-logrotate.md           # PM2 log rotation module — daily rotation, 7-day retention, gzip compression
│       ├── config-version-control.md  # Git tracking for docker/ and appdata configs
│       ├── jobsearch-mcp.md           # Multi-board job search, resume scoring, application tracking
│       ├── agent-orchestration.md     # Task queue, agent manifests, dispatcher
│       ├── nats-jetstream.md          # Agent event bus — JetStream streams, task lifecycle subjects
│       ├── n8n.md                     # Webhook workflow engine — visual task routing, ntfy alerting, Postgres-backed
│       ├── plane.md                   # Self-hosted project management — Helm tracking, 11-container stack, MCP integration
│       ├── claudebox-deploy.md        # Deploy script, rebuild workflow
│       ├── inter-agent-communication.md # Agent-to-agent messaging patterns
│       ├── security-agent.md          # Security audit agent, triage workflow
│       ├── helm-dashboard.md          # CloudCLI plugin — monitoring tab for walk-away builds
│       ├── auto-mode.md               # Claude Code auto permission mode — settings.json rules, CloudCLI SDK patch
│       ├── temporal.md                # Temporal durable workflow engine — multi-phase build automation, 5-container stack
│       ├── helm-temporal-worker.md    # Helm Temporal Worker — PM2 bridge from Temporal to Claude Code agents
│       ├── task-dispatcher.md         # Task dispatcher — PM2 cron for agent task queue routing and approval gating
│       ├── task-queue-mcp.md          # Task Queue MCP — FastMCP server, typed task queue tool access, schema enforcement
│       ├── trigger-proxy.md           # Trigger Proxy — PM2 OAuth bridge for n8n Docker → claude.ai RemoteTrigger
│       ├── memory-pipeline.md         # Memory pipeline — nightly consolidation orchestrator, tiered schedule
│       ├── agent-bus.md               # Agent Bus — FastMCP inter-agent event log, NATS JetStream federation
│       ├── backups.md                 # Backup strategy: Backrest/restic, Claude backup, Docker appdata
│       ├── multi-host.md             # Multi-host abstraction boundary design document
│       ├── doc-sync.md               # doc-sync documentation cache — upstream fetch, chunk, memsearch index
│       ├── helm-ops-mcp.md           # helm-ops SSH-based MCP server for remote Helm host operations
│       ├── librarian-weekly.md       # Weekly PM2 cron — prime-directive repo sync via librarian skill
│       ├── repo-sync-nightly.md      # Nightly repo hygiene — auto-commit doc repos, alert on dirty code repos
│       ├── blog-preview.md           # Local MkDocs Material preview server for blog article drafting
│       ├── scoped-mcp.md             # Per-agent MCP tool proxy — manifest-driven scoping, credential isolation, audit log
│       ├── hister.md                 # Hister browser history search — Docker stack, SWAG proxy, memsearch integration
│       ├── ollama-queue-proxy.md     # Ollama smart pool manager — auth, priority queuing, model-aware routing, embedding cache
│       ├── ollama-auth-sidecar.md    # Nginx auth sidecar — Bearer token injection for native Ollama clients
│       ├── matrix.md                 # Matrix agent communications — Synapse homeserver, matrix-mcp, operator notification layer
│       ├── ketesa.md                 # Ketesa Matrix admin UI — Synapse web admin interface, SWAG vhost, LAN-restricted admin API
│       └── matrix-dispatcher.md     # Matrix Dispatcher — PM2 daemon, Element Web operator interface, SQLite session resume, bang-prefix commands
├── claude-code/
│   ├── CLAUDE.md.example              # Root CLAUDE.md template
│   └── projects/
│       ├── homelab-ops.md             # Infrastructure management agent config
│       ├── dev.md                     # Development agent config
│       ├── research.md                # Research agent config
│       ├── security.md               # Security audit agent config
│       └── memory-sync.md            # Memory distillation agent config
├── docker/
│   ├── swag/                          # SWAG reverse proxy compose
│   ├── authelia/                      # Authelia SSO compose
│   ├── librechat/                     # LibreChat compose + config
│   ├── firecrawl-simple/              # Web scraper for LibreChat search pipeline
│   ├── reranker/                      # Jina-compatible FlashRank reranker
│   ├── dockhand/                      # Dockhand Docker stack manager compose
│   ├── jobsearch/                     # jobsearch-mcp stack (MCP server + Postgres + Qdrant)
│   └── open-notebook/                 # Open Notebook + SurrealDB compose
├── mcp-servers/
│   └── README.md                      # MCP server reference, config patterns, adoption path
├── pm2/
│   └── ecosystem.config.js.example    # PM2 service + cron definitions
└── scripts/
    ├── docker-stack-backup.sh         # Container-safe appdata backup with notifications
    ├── qmd-reindex.sh                 # Semantic search re-indexing
    ├── memory-sync.sh                 # Automated knowledge distillation
    ├── check-resources.sh             # Health monitoring with push alerts
    ├── check-dep-updates.sh           # Dependency update checker
    └── git-snapshot.sh                # Nightly git commit of uncommitted config changes
```

## Context Loading Guide

Use these mappings to load only the docs relevant to your task. Paths are relative to repo root.

### By Topic

| Topic | Load These | Skip These |
|-------|-----------|------------|
| Architecture overview | `README.md` (§Architecture) | Everything else |
| MCP server setup | `mcp-servers/README.md` | Docker, Claude Code |
| homelab-ops MCP | `docs/components/homelab-ops-mcp.md`, `mcp-servers/README.md` (§homelab-ops) | Docker compose, Claude Code |
| LibreChat / web search | `docs/components/librechat.md`, `docker/librechat/`, `docker/firecrawl-simple/`, `docker/reranker/` | MCP, Claude Code, PM2 |
| Reverse proxy / SSL | `docs/components/swag.md`, `docker/swag/` | Claude Code, MCP |
| SSO / authentication | `docs/components/authelia.md`, `docker/authelia/` | Claude Code, MCP |
| AI search (SearXNG) | `docs/components/searxng.md` | Claude Code, MCP |
| Docker management (Dockhand) | `docs/components/dockhand.md`, `docker/dockhand/` | Claude Code, MCP |
| AI notebook (Open Notebook) | `docs/components/open-notebook.md`, `docker/open-notebook/` | Claude Code, MCP |
| Claude Code browser UI (CloudCLI) | `docs/components/cloudcli.md` | Docker, MCP |
| Homelab operations panel | `docs/components/agent-panel.md` | Docker compose, MCP |
| Scheduled diagnostics | `docs/components/diag-check.md`, `docs/components/agent-panel.md` | Docker compose, MCP |
| Agent observability (Grafana) | `docs/components/grafana-claudebox.md` | MCP, Claude Code |
| AI cost tracking | `docs/components/ai-cost-tracking.md` | Docker, MCP |
| Job search agent | `docs/components/jobsearch-mcp.md`, `docker/jobsearch/` | Claude Code, MCP |
| Config version control | `docs/components/config-version-control.md` | MCP, Claude Code |
| Claude Code / CLAUDE.md | `claude-code/CLAUDE.md.example`, `claude-code/projects/` | Docker, MCP |
| PM2 MCP server | `docs/components/pm2-mcp.md` | Claude Code, MCP |
| Per-agent MCP scoping | `docs/components/scoped-mcp.md` | Claude Code, MCP |
| Ollama proxy / queue management | `docs/components/ollama-queue-proxy.md` | Docker, MCP |
| Ollama auth sidecar | `docs/components/ollama-auth-sidecar.md` | Docker, MCP |
| Matrix agent communications | `docs/components/matrix.md` | Docker, Claude Code |
| Matrix admin UI (Ketesa) | `docs/components/ketesa.md` | Docker, Claude Code |
| Matrix Dispatcher (agent rooms) | `docs/components/matrix-dispatcher.md` | PM2, Claude Code |
| PM2 services / cron | `pm2/ecosystem.config.js.example` | Docker compose, MCP config |
| Memory system | `README.md` (§The Memory / Context System), `docs/components/memsearch.md`, `docs/components/memory-sync.md`, `docs/components/graphiti.md`, `claude-code/projects/memory-sync.md` | Docker, MCP |
| Documentation health | `docs/components/doc-health.md` | Docker, MCP |
| Backups | `docs/components/backups.md`, `scripts/docker-stack-backup.sh`, `pm2/ecosystem.config.js.example` | Docker compose, MCP, Claude Code |
| Docker stacks (general) | `docker/` subdirectories | Claude Code, MCP |
| Semantic search (qmd) | `docs/components/qmd.md`, `mcp-servers/README.md` (§qmd) | Docker, Claude Code |
| Getting started | `docs/getting-started.md` | Component-level docs |
| Detailed architecture | `docs/architecture.md` | Component-level docs |

### By Architecture Layer

| Layer | Primary Docs | Config Files |
|-------|-------------|-------------|
| Layer 1 — Host & Core Tooling | `README.md` (§Layer 1), `mcp-servers/README.md`, `docs/components/homelab-ops-mcp.md` | `claude_desktop_config.json` patterns in `mcp-servers/README.md` |
| Layer 2 — Self-Hosted Services | `README.md` (§Layer 2), `docs/components/*.md` | `docker/*/docker-compose.yml` |
| Layer 3 — Multi-Agent Engine | `README.md` (§Layer 3), `claude-code/`, `docs/components/memsearch.md`, `docs/components/memory-sync.md`, `docs/components/graphiti.md` | `pm2/ecosystem.config.js.example`, `claude-code/projects/*.md` |

### By Task

| Task | Start Here |
|------|-----------| 
| "I want to understand the overall system" | `README.md` — read top-to-bottom |
| "I want to set up MCP servers" | `mcp-servers/README.md` — has adoption path and all config patterns |
| "I want to deploy LibreChat with web search" | `docs/components/librechat.md` — then `docker/librechat/` and `docker/firecrawl-simple/` |
| "I want to set up reverse proxy + SSO" | `docs/components/swag.md` → `docs/components/authelia.md` — then `docker/swag/` and `docker/authelia/` |
| "I want to deploy SearXNG" | `docs/components/searxng.md` |
| "I want a browser-based Claude Code UI" | `docs/components/cloudcli.md` — interactive sessions, file explorer, git integration |
| "I want to monitor headless agent runs" | `docs/components/agent-panel.md` — operations panel for PM2 services, Docker, diagnostics |
| "I want project/task tracking for homelab builds" | `docs/components/plane.md` — Plane setup, MCP integration, SWAG multi-path proxy |
| "I want a live dashboard for unattended agent builds" | `docs/components/helm-dashboard.md` — CloudCLI plugin; then `docs/components/auto-mode.md` for walk-away permission config |
| "I want durable workflow execution for multi-phase builds" | `docs/components/temporal.md` — then `docs/components/agent-orchestration.md` for the task queue and dispatcher |
| "I want Claude Code to auto-approve routine operations" | `docs/components/auto-mode.md` — settings.json permission rules and CloudCLI SDK patch |
| "I want to track Claude API costs" | `docs/components/ai-cost-tracking.md` — then `docs/components/grafana-claudebox.md` |
| "I want version control on my Docker configs" | `docs/components/config-version-control.md` |
| "I want to set up Claude Code agents" | `claude-code/CLAUDE.md.example` — then `claude-code/projects/` for per-agent examples |
| "I want to add PM2 background jobs" | `pm2/ecosystem.config.js.example` — self-contained |
| "I want to replicate the memory system" | `README.md` (§Memory / Context System) → `docs/components/memsearch.md` → `docs/components/memory-sync.md` → `docs/components/graphiti.md` |
| "I want to build a custom reranker" | `docker/reranker/` — standalone Dockerfile + source |
| "I want to set up the whole thing step by step" | `docs/getting-started.md` — dependency-ordered with stopping points |
| "I want to understand data flows and topology" | `docs/architecture.md` — detailed system architecture |
| "I want to understand the backup strategy" | `docs/components/backups.md` — all three backup mechanisms, schedules, retention, restore guidance |

## Document Status

| Document | Status | Last Substantive Update |
|----------|--------|------------------------|
| `README.md` | ✅ Complete | 2026-03 |
| `mcp-servers/README.md` | ✅ Complete | 2026-03 |
| `claude-code/CLAUDE.md.example` | ✅ Complete | 2026-03 |
| `claude-code/projects/*.md` | ✅ Complete | 2026-03 |
| `pm2/ecosystem.config.js.example` | ✅ Complete | 2026-03 |
| `docs/components/README.md` | ✅ Complete | 2026-03 |
| `docs/components/librechat.md` | ✅ Complete | 2026-03 |
| `docs/components/swag.md` | ✅ Complete | 2026-03 |
| `docs/components/authelia.md` | ✅ Complete | 2026-03 |
| `docs/components/searxng.md` | ✅ Complete | 2026-03 |
| `docs/components/searxng-mcp.md` | ✅ Complete | 2026-04 |
| `docs/components/crawl4ai.md` | ✅ Complete | 2026-04 |
| `docs/components/dockhand.md` | ✅ Complete | 2026-03 |
| `docs/components/open-notebook.md` | ✅ Complete | 2026-03 |
| `docs/components/cloudcli.md` | ✅ Complete | 2026-03 |
| `docs/components/agent-panel.md` | ✅ Complete | 2026-03 |
| `docs/components/agent-workspace-check.md` | ✅ Complete | 2026-03 |
| `docs/components/agent-workspace-scan.md` | ✅ Complete | 2026-03 |
| `docs/components/diag-check.md` | ✅ Complete | 2026-03 |
| `docs/components/grafana-claudebox.md` | ✅ Complete | 2026-03 |
| `docs/components/grafana-observability.md` | ✅ Complete | 2026-03 |
| `docs/components/qmd.md` | ✅ Complete | 2026-03 |
| `docs/components/memsearch.md` | ✅ Complete | 2026-03 |
| `docs/components/memory-sync.md` | ✅ Complete | 2026-03 |
| `docs/components/graphiti.md` | ✅ Complete | 2026-03 |
| `docs/components/graphiti-mcp.md` | ✅ Complete | 2026-04 |
| `docs/components/nats-jetstream.md` | ✅ Complete | 2026-03 |
| `docs/components/n8n.md` | ✅ Complete | 2026-03 |
| `docs/components/doc-health.md` | ✅ Complete | 2026-03 |
| `docs/components/ai-cost-tracking.md` | ✅ Complete | 2026-03 |
| `docs/components/homelab-ops-mcp.md` | ✅ Complete | 2026-03 |
| `docs/components/ntfy-mcp.md` | ✅ Complete | 2026-04 |
| `docs/components/pm2-logrotate.md` | ✅ Complete | 2026-04 |
| `docs/components/config-version-control.md` | ✅ Complete | 2026-03 |
| `docs/components/jobsearch-mcp.md` | ✅ Complete | 2026-03 |
| `docs/components/backups.md` | ✅ Complete | 2026-03 |
| `docs/components/agent-orchestration.md` | ✅ Complete | 2026-03 |
| `docs/components/claudebox-deploy.md` | ✅ Complete | 2026-03 |
| `docs/components/inter-agent-communication.md` | ✅ Complete | 2026-03 |
| `docs/components/security-agent.md` | ✅ Complete | 2026-03 |
| `docker/swag/` | ✅ Complete | 2026-03 |
| `docker/authelia/` | ✅ Complete | 2026-03 |
| `docker/dockhand/` | ✅ Complete | 2026-03 |
| `docker/open-notebook/` | ✅ Complete | 2026-03 |
| `docker/librechat/` | ✅ Complete | 2026-03 |
| `docker/firecrawl-simple/` | ✅ Complete | 2026-03 |
| `docker/reranker/` | ✅ Complete | 2026-03 |
| `docker/jobsearch/` | ✅ Complete | 2026-03 |
| `docs/components/plane.md` | ✅ Complete | 2026-03 |
| `docs/components/helm-dashboard.md` | ✅ Complete | 2026-03 |
| `docs/components/auto-mode.md` | ✅ Complete | 2026-03 |
| `docs/components/temporal.md` | ✅ Complete | 2026-03 |
| `docs/components/helm-temporal-worker.md` | ✅ Complete | 2026-03 |
| `docs/components/task-dispatcher.md` | ✅ Complete | 2026-03 |
| `docs/components/task-queue-mcp.md` | ✅ Complete | 2026-04 |
| `docs/components/trigger-proxy.md` | ✅ Complete | 2026-04 |
| `docs/components/memory-pipeline.md` | ✅ Complete | 2026-03 |
| `docs/components/agent-bus.md` | ✅ Complete | 2026-03 |
| `docs/components/blog-preview.md` | ✅ Complete | 2026-04 |
| `docs/components/scoped-mcp.md` | ✅ Complete | 2026-04 |
| `docs/components/hister.md` | ✅ Complete | 2026-04 |
| `docs/components/ollama-queue-proxy.md` | ✅ Complete | 2026-04 |
| `docs/components/ollama-auth-sidecar.md` | ✅ Complete | 2026-04 |
| `docs/components/matrix.md` | ✅ Complete | 2026-04 |
| `docs/components/ketesa.md` | ✅ Complete | 2026-04 |
| `docs/components/matrix-dispatcher.md` | ✅ Complete | 2026-04 |
| `docs/architecture.md` | ✅ Complete | 2026-03 |
| `docs/getting-started.md` | ✅ Complete | 2026-03 |
| `scripts/` | ✅ Complete | 2026-03 |

## Cross-Reference: Components → Documents

| Component | Docs | Config | Compose |
|-----------|------|--------|---------|
| LibreChat | [`docs/components/librechat.md`](docs/components/librechat.md) | `docker/librechat/librechat.yaml.example` | `docker/librechat/docker-compose.yml` |
| firecrawl-simple | [`docs/components/librechat.md`](docs/components/librechat.md) (§Web Search Pipeline) | — | `docker/firecrawl-simple/docker-compose.yml` |
| Reranker | [`docs/components/librechat.md`](docs/components/librechat.md) (§Rerank) | — | `docker/reranker/docker-compose.yml` |
| SWAG | [`docs/components/swag.md`](docs/components/swag.md) | — | `docker/swag/docker-compose.yml` |
| Authelia | [`docs/components/authelia.md`](docs/components/authelia.md) | — | `docker/authelia/docker-compose.yml` |
| SearXNG | [`docs/components/searxng.md`](docs/components/searxng.md) | — | (compose not in repo) |
| SearXNG MCP | [`docs/components/searxng-mcp.md`](docs/components/searxng-mcp.md) | — | (PM2 host service) |
| Crawl4AI | [`docs/components/crawl4ai.md`](docs/components/crawl4ai.md) | — | (Docker container) |
| Dockhand | [`docs/components/dockhand.md`](docs/components/dockhand.md) | — | `docker/dockhand/docker-compose.yml` |
| Open Notebook | [`docs/components/open-notebook.md`](docs/components/open-notebook.md) | — | `docker/open-notebook/docker-compose.yml` |
| CloudCLI | [`docs/components/cloudcli.md`](docs/components/cloudcli.md) | — | (PM2 host service) |
| Agent Panel | [`docs/components/agent-panel.md`](docs/components/agent-panel.md) | — | (PM2 host service) |
| Agent Workspace Check | [`docs/components/agent-workspace-check.md`](docs/components/agent-workspace-check.md) | — | (Skill / pre-edit hook) |
| Agent Workspace Scan | [`docs/components/agent-workspace-scan.md`](docs/components/agent-workspace-scan.md) | — | (PM2 cron job) |
| Diag-Check | [`docs/components/diag-check.md`](docs/components/diag-check.md) | — | (PM2 cron job) |
| Grafana claudebox | [`docs/components/grafana-claudebox.md`](docs/components/grafana-claudebox.md) | — | (compose not in repo) |
| Grafana Observability | [`docs/components/grafana-observability.md`](docs/components/grafana-observability.md) | — | (compose not in repo) |
| qmd | [`docs/components/qmd.md`](docs/components/qmd.md), [`mcp-servers/README.md`](mcp-servers/README.md) (§qmd) | — | (host-level service) |
| memsearch | [`docs/components/memsearch.md`](docs/components/memsearch.md) | `~/.memsearch/config.toml` | (host-level service) |
| memory-sync | [`docs/components/memory-sync.md`](docs/components/memory-sync.md), [`claude-code/projects/memory-sync.md`](claude-code/projects/memory-sync.md) | — | (PM2 cron job) |
| Graphiti | [`docs/components/graphiti.md`](docs/components/graphiti.md) | `config.yaml`, `.env` | (Docker stack: neo4j + graphiti-mcp) |
| Graphiti MCP | [`docs/components/graphiti-mcp.md`](docs/components/graphiti-mcp.md) | — | (Docker container, graphiti-internal network) |
| doc-health | [`docs/components/doc-health.md`](docs/components/doc-health.md) | — | (PM2 cron job) |
| AI Cost Tracking | [`docs/components/ai-cost-tracking.md`](docs/components/ai-cost-tracking.md) | — | (host script + PM2) |
| homelab-ops MCP | [`docs/components/homelab-ops-mcp.md`](docs/components/homelab-ops-mcp.md), [`mcp-servers/README.md`](mcp-servers/README.md) (§homelab-ops) | — | (PM2 host service) |
| ntfy-mcp | [`docs/components/ntfy-mcp.md`](docs/components/ntfy-mcp.md) | `~/docker/ntfy-mcp/.env` | `~/docker/ntfy-mcp/docker-compose.yml` |
| pm2-logrotate | [`docs/components/pm2-logrotate.md`](docs/components/pm2-logrotate.md) | — | — |
| Config Version Control | [`docs/components/config-version-control.md`](docs/components/config-version-control.md) | — | — |
| jobsearch-mcp | [`docs/components/jobsearch-mcp.md`](docs/components/jobsearch-mcp.md), [`mcp-servers/README.md`](mcp-servers/README.md) (§jobsearch-mcp) | `.env` | `docker/jobsearch/docker-compose.yml` |
| n8n | [`docs/components/n8n.md`](docs/components/n8n.md) | `~/docker/n8n/.env` | `~/docker/n8n/docker-compose.yml` |
| MCP servers (all) | [`mcp-servers/README.md`](mcp-servers/README.md) | Config patterns inline | — |
| PM2 services | [`pm2/ecosystem.config.js.example`](pm2/ecosystem.config.js.example) | Inline | — |
| CLAUDE.md hierarchy | [`claude-code/CLAUDE.md.example`](claude-code/CLAUDE.md.example), [`claude-code/projects/`](claude-code/projects/) | — | — |
| NATS JetStream | [`docs/components/nats-jetstream.md`](docs/components/nats-jetstream.md) | — | (Docker container) |
| Agent Orchestration | [`docs/components/agent-orchestration.md`](docs/components/agent-orchestration.md) | — | (PM2 service) |
| Claudebox Deploy | [`docs/components/claudebox-deploy.md`](docs/components/claudebox-deploy.md) | — | — |
| Inter-Agent Communication | [`docs/components/inter-agent-communication.md`](docs/components/inter-agent-communication.md) | — | — |
| Security Agent | [`docs/components/security-agent.md`](docs/components/security-agent.md) | — | — |
| Plane | [`docs/components/plane.md`](docs/components/plane.md) | `~/docker/plane/.env` | `~/docker/plane/docker-compose.yml` |
| Helm Dashboard | [`docs/components/helm-dashboard.md`](docs/components/helm-dashboard.md) | `~/.claude-code-ui/plugins/cloudcli-plugin-helm-dashboard/config.json` | (CloudCLI plugin) |
| Auto Mode | [`docs/components/auto-mode.md`](docs/components/auto-mode.md) | `~/.claude/settings.json`, `~/.claude/projects/<project>/settings.json` | — |
| Temporal | [`docs/components/temporal.md`](docs/components/temporal.md) | `~/docker/temporal/.env` | `~/docker/temporal/docker-compose.yml` |
| Helm Temporal Worker | [`docs/components/helm-temporal-worker.md`](docs/components/helm-temporal-worker.md) | — | (PM2 host service) |
| Task Dispatcher | [`docs/components/task-dispatcher.md`](docs/components/task-dispatcher.md) | — | (PM2 cron job) |
| Trigger Proxy | [`docs/components/trigger-proxy.md`](docs/components/trigger-proxy.md) | — | (PM2 host service) |
| Task Queue MCP | [`docs/components/task-queue-mcp.md`](docs/components/task-queue-mcp.md) | — | (Docker container, PM2-managed) |
| Memory Pipeline | [`docs/components/memory-pipeline.md`](docs/components/memory-pipeline.md) | — | (PM2 cron jobs) |
| Agent Bus | [`docs/components/agent-bus.md`](docs/components/agent-bus.md) | — | (PM2 host service + NATS) |
| Hister | [`docs/components/hister.md`](docs/components/hister.md) | — | `docker/hister/docker-compose.yml` |
| ollama-queue-proxy | [`docs/components/ollama-queue-proxy.md`](docs/components/ollama-queue-proxy.md) | `/opt/appdata/ollama-queue-proxy/config.yml` | `docker/ollama-queue-proxy/docker-compose.yml` |
| ollama-auth-sidecar | [`docs/components/ollama-auth-sidecar.md`](docs/components/ollama-auth-sidecar.md) | — | (Docker sidecar) |
| Matrix Agent Comms | [`docs/components/matrix.md`](docs/components/matrix.md) | — | (Docker stack + PM2) |
| Ketesa | [`docs/components/ketesa.md`](docs/components/ketesa.md) | — | (Docker container, SWAG vhost) |
| Matrix Dispatcher | [`docs/components/matrix-dispatcher.md`](docs/components/matrix-dispatcher.md) | — | (PM2 host service) |
| Backups | [`docs/components/backups.md`](docs/components/backups.md) | [`scripts/docker-stack-backup.sh`](scripts/docker-stack-backup.sh) | (Backrest systemd + PM2 cron + user crontab) |
| Blog Preview | [`docs/components/blog-preview.md`](docs/components/blog-preview.md) | — | (Docker container, claudebox-net) |
| scoped-mcp | [`docs/components/scoped-mcp.md`](docs/components/scoped-mcp.md) | `manifests/<agent-type>.yml` | (stdio subprocess, one per agent) |
