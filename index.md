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
│   └── components/
│       ├── swag.md                    # SWAG reverse proxy, Cloudflare DNS, proxy conf pattern
│       ├── authelia.md                # Authelia SSO, file-based user backend, SWAG integration
│       ├── librechat.md               # LibreChat setup, web search pipeline, reranker
│       ├── searxng.md               # SearXNG + Valkey, search backend
│       ├── dockhand.md                # Dockhand Docker stack manager, socket access
│       ├── open-notebook.md           # Open Notebook AI research, SurrealDB, dual-port proxy
│       ├── qmd.md                     # qmd semantic search, dual transport, GPU acceleration
│       ├── memsearch.md               # memsearch memory recall for Claude Code sessions
│       ├── memory-sync.md             # Automated knowledge distillation pipeline
│       └── backups.md                 # Backup strategy: Backrest/restic, Claude backup, Docker appdata
├── claude-code/
│   ├── CLAUDE.md.example              # Root CLAUDE.md template
│   └── projects/
│       ├── homelab-ops.md             # Infrastructure management agent config
│       ├── dev.md                     # Development agent config
│       ├── research.md                # Research agent config
│       └── memory-sync.md            # Memory distillation agent config
├── docker/
│   ├── swag/                          # SWAG reverse proxy compose
│   ├── authelia/                      # Authelia SSO compose
│   ├── librechat/                     # LibreChat compose + config
│   ├── firecrawl-simple/              # Web scraper for LibreChat search pipeline
│   ├── reranker/                      # Jina-compatible FlashRank reranker
│   ├── searxng/                    # SearXNG + Valkey compose
│   ├── dockhand/                      # Dockhand Docker stack manager compose
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
    └── check-dep-updates.sh           # Dependency update checker
```

## Context Loading Guide

Use these mappings to load only the docs relevant to your task. Paths are relative to repo root.

### By Topic

| Topic | Load These | Skip These |
|-------|-----------|------------|
| Architecture overview | `README.md` (§Architecture) | Everything else |
| MCP server setup | `mcp-servers/README.md` | Docker, Claude Code |
| LibreChat / web search | `docs/components/librechat.md`, `docker/librechat/`, `docker/firecrawl-simple/`, `docker/reranker/` | MCP, Claude Code, PM2 |
| Reverse proxy / SSL | `docs/components/swag.md`, `docker/swag/` | Claude Code, MCP |
| SSO / authentication | `docs/components/authelia.md`, `docker/authelia/` | Claude Code, MCP |
| AI search (SearXNG) | `docs/components/searxng.md`, `docker/searxng/` | Claude Code, MCP |
| Docker management (Dockhand) | `docs/components/dockhand.md`, `docker/dockhand/` | Claude Code, MCP |
| AI notebook (Open Notebook) | `docs/components/open-notebook.md`, `docker/open-notebook/` | Claude Code, MCP |
| Claude Code / CLAUDE.md | `claude-code/CLAUDE.md.example`, `claude-code/projects/` | Docker, MCP |
| PM2 services / cron | `pm2/ecosystem.config.js.example` | Docker compose, MCP config |
| Memory system | `README.md` (§The Memory / Context System), `docs/components/memsearch.md`, `docs/components/memory-sync.md`, `claude-code/projects/memory-sync.md` | Docker, MCP |
| Backups | `docs/components/backups.md`, `scripts/docker-stack-backup.sh`, `pm2/ecosystem.config.js.example` | Docker compose, MCP, Claude Code |
| Docker stacks (general) | `docker/` subdirectories | Claude Code, MCP |
| Semantic search (qmd) | `docs/components/qmd.md`, `mcp-servers/README.md` (§qmd) | Docker, Claude Code |
| Getting started | `docs/getting-started.md` | Component-level docs |
| Detailed architecture | `docs/architecture.md` | Component-level docs |

### By Architecture Layer

| Layer | Primary Docs | Config Files |
|-------|-------------|-------------|
| Layer 1 — Host & Core Tooling | `README.md` (§Layer 1), `mcp-servers/README.md` | `claude_desktop_config.json` patterns in `mcp-servers/README.md` |
| Layer 2 — Self-Hosted Services | `README.md` (§Layer 2), `docs/components/*.md` | `docker/*/docker-compose.yml` |
| Layer 3 — Multi-Agent Engine | `README.md` (§Layer 3), `claude-code/`, `docs/components/memsearch.md`, `docs/components/memory-sync.md` | `pm2/ecosystem.config.js.example`, `claude-code/projects/*.md` |

### By Task

| Task | Start Here |
|------|-----------|
| "I want to understand the overall system" | `README.md` — read top-to-bottom |
| "I want to set up MCP servers" | `mcp-servers/README.md` — has adoption path and all config patterns |
| "I want to deploy LibreChat with web search" | `docs/components/librechat.md` — then `docker/librechat/` and `docker/firecrawl-simple/` |
| "I want to set up reverse proxy + SSO" | `docs/components/swag.md` → `docs/components/authelia.md` — then `docker/swag/` and `docker/authelia/` |
| "I want to deploy SearXNG" | `docs/components/searxng.md` — then `docker/searxng/` |
| "I want to set up Claude Code agents" | `claude-code/CLAUDE.md.example` — then `claude-code/projects/` for per-agent examples |
| "I want to add PM2 background jobs" | `pm2/ecosystem.config.js.example` — self-contained |
| "I want to replicate the memory system" | `README.md` (§Memory / Context System) → `docs/components/memsearch.md` → `docs/components/memory-sync.md` |
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
| `docs/components/librechat.md` | ✅ Complete | 2026-03 |
| `docs/components/swag.md` | ✅ Complete | 2026-03 |
| `docs/components/authelia.md` | ✅ Complete | 2026-03 |
| `docs/components/searxng.md` | ✅ Complete | 2026-03 |
| `docs/components/dockhand.md` | ✅ Complete | 2026-03 |
| `docs/components/open-notebook.md` | ✅ Complete | 2026-03 |
| `docker/swag/` | ✅ Complete | 2026-03 |
| `docker/authelia/` | ✅ Complete | 2026-03 |
| `docker/searxng/` | ✅ Complete | 2026-03 |
| `docker/dockhand/` | ✅ Complete | 2026-03 |
| `docker/open-notebook/` | ✅ Complete | 2026-03 |
| `docker/librechat/` | ✅ Complete | 2026-03 |
| `docker/firecrawl-simple/` | ✅ Complete | 2026-03 |
| `docker/reranker/` | ✅ Complete | 2026-03 |
| `docs/architecture.md` | ✅ Complete | 2026-03 |
| `docs/getting-started.md` | ✅ Complete | 2026-03 |
| `docs/components/qmd.md` | ✅ Complete | 2026-03 |
| `docs/components/memsearch.md` | ✅ Complete | 2026-03 |
| `docs/components/memory-sync.md` | ✅ Complete | 2026-03 |
| `docs/components/backups.md` | ✅ Complete | 2026-03 |
| `scripts/` | ✅ Complete | 2026-03 |

## Cross-Reference: Components → Documents

| Component | Docs | Config | Compose |
|-----------|------|--------|---------|
| LibreChat | [`docs/components/librechat.md`](docs/components/librechat.md) | `docker/librechat/librechat.yaml.example` | `docker/librechat/docker-compose.yml` |
| firecrawl-simple | [`docs/components/librechat.md`](docs/components/librechat.md) (§Web Search Pipeline) | — | `docker/firecrawl-simple/docker-compose.yml` |
| Reranker | [`docs/components/librechat.md`](docs/components/librechat.md) (§Rerank) | — | `docker/reranker/docker-compose.yml` |
| SWAG | [`docs/components/swag.md`](docs/components/swag.md) | — | `docker/swag/docker-compose.yml` |
| Authelia | [`docs/components/authelia.md`](docs/components/authelia.md) | — | `docker/authelia/docker-compose.yml` |
| qmd | [`docs/components/qmd.md`](docs/components/qmd.md), [`mcp-servers/README.md`](mcp-servers/README.md) (§qmd) | — | (host-level service) |
| SearXNG | [`docs/components/searxng.md`](docs/components/searxng.md) | — | `docker/searxng/docker-compose.yml` |
| Dockhand | [`docs/components/dockhand.md`](docs/components/dockhand.md) | — | `docker/dockhand/docker-compose.yml` |
| Open Notebook | [`docs/components/open-notebook.md`](docs/components/open-notebook.md) | — | `docker/open-notebook/docker-compose.yml` |
| MCP servers (all) | [`mcp-servers/README.md`](mcp-servers/README.md) | Config patterns inline | — |
| PM2 services | [`pm2/ecosystem.config.js.example`](pm2/ecosystem.config.js.example) | Inline | — |
| CLAUDE.md hierarchy | [`claude-code/CLAUDE.md.example`](claude-code/CLAUDE.md.example), [`claude-code/projects/`](claude-code/projects/) | — | — |
| memsearch | [`docs/components/memsearch.md`](docs/components/memsearch.md) | `~/.memsearch/config.toml` | (host-level service) |
| memory-sync | [`docs/components/memory-sync.md`](docs/components/memory-sync.md), [`claude-code/projects/memory-sync.md`](claude-code/projects/memory-sync.md) | — | (PM2 cron job) |
| Backups | [`docs/components/backups.md`](docs/components/backups.md) | [`scripts/docker-stack-backup.sh`](scripts/docker-stack-backup.sh) | (Backrest systemd + PM2 cron + user crontab) |
