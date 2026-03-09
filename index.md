# homelab-agent — Document Index

Machine-readable index for AI agents navigating this repo. Load only the sections relevant to your current task — don't load everything.

## Repo Map

```
homelab-agent/
├── README.md                          # Architecture overview, origin story, component guide
├── index.md                           # THIS FILE — agent navigation index
├── docs/
│   └── components/
│       ├── swag.md                    # SWAG reverse proxy, Cloudflare DNS, proxy conf pattern
│       ├── authelia.md                # Authelia SSO, file-based user backend, SWAG integration
│       ├── librechat.md               # LibreChat setup, web search pipeline, reranker
│       ├── perplexica.md              # Perplexica AI search, SearXNG, shared search backend
│       ├── dockhand.md                # Dockhand Docker stack manager, socket access
│       └── open-notebook.md           # Open Notebook AI research, SurrealDB, dual-port proxy
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
│   ├── perplexica/                    # Perplexica + SearXNG + Valkey compose
│   ├── dockhand/                      # Dockhand Docker stack manager compose
│   └── open-notebook/                 # Open Notebook + SurrealDB compose
├── mcp-servers/
│   └── README.md                      # MCP server reference, config patterns, adoption path
└── pm2/
    └── ecosystem.config.js.example    # PM2 service + cron definitions
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
| AI search (Perplexica) | `docs/components/perplexica.md`, `docker/perplexica/` | Claude Code, MCP |
| Docker management (Dockhand) | `docs/components/dockhand.md`, `docker/dockhand/` | Claude Code, MCP |
| AI notebook (Open Notebook) | `docs/components/open-notebook.md`, `docker/open-notebook/` | Claude Code, MCP |
| Claude Code / CLAUDE.md | `claude-code/CLAUDE.md.example`, `claude-code/projects/` | Docker, MCP |
| PM2 services / cron | `pm2/ecosystem.config.js.example` | Docker compose, MCP config |
| Memory system | `README.md` (§The Memory / Context System), `claude-code/projects/memory-sync.md` | Docker, MCP |
| Docker stacks (general) | `docker/` subdirectories | Claude Code, MCP |
| Reverse proxy / SSO | `docs/components/swag.md`, `docs/components/authelia.md`, `docker/swag/`, `docker/authelia/` | Claude Code, MCP |
| Semantic search (qmd) | `mcp-servers/README.md` (§qmd), `README.md` (§Layer 2 qmd row) | Docker, Claude Code |
| Getting started | `README.md` (§Prerequisites, §What's in This Repo) | Component-level docs |

### By Architecture Layer

| Layer | Primary Docs | Config Files |
|-------|-------------|-------------|
| Layer 1 — Host & Core Tooling | `README.md` (§Layer 1), `mcp-servers/README.md` | `claude_desktop_config.json` patterns in `mcp-servers/README.md` |
| Layer 2 — Self-Hosted Services | `README.md` (§Layer 2), `docs/components/*.md` | `docker/*/docker-compose.yml` |
| Layer 3 — Multi-Agent Engine | `README.md` (§Layer 3), `claude-code/` | `pm2/ecosystem.config.js.example`, `claude-code/projects/*.md` |

### By Task

| Task | Start Here |
|------|-----------|
| "I want to understand the overall system" | `README.md` — read top-to-bottom |
| "I want to set up MCP servers" | `mcp-servers/README.md` — has adoption path and all config patterns |
| "I want to deploy LibreChat with web search" | `docs/components/librechat.md` — then `docker/librechat/` and `docker/firecrawl-simple/` |
| "I want to set up reverse proxy + SSO" | `docs/components/swag.md` → `docs/components/authelia.md` — then `docker/swag/` and `docker/authelia/` |
| "I want to deploy Perplexica" | `docs/components/perplexica.md` — then `docker/perplexica/` |
| "I want to set up Claude Code agents" | `claude-code/CLAUDE.md.example` — then `claude-code/projects/` for per-agent examples |
| "I want to add PM2 background jobs" | `pm2/ecosystem.config.js.example` — self-contained |
| "I want to replicate the memory system" | `README.md` (§Memory / Context System) → `claude-code/projects/memory-sync.md` |
| "I want to build a custom reranker" | `docker/reranker/` — standalone Dockerfile + source |

## Document Status

| Document | Status | Last Substantive Update |
|----------|--------|------------------------|
| `README.md` | ✅ Complete | 2025-03 |
| `mcp-servers/README.md` | ✅ Complete | 2025-03 |
| `claude-code/CLAUDE.md.example` | ✅ Complete | 2025-03 |
| `claude-code/projects/*.md` | ✅ Complete | 2025-03 |
| `pm2/ecosystem.config.js.example` | ✅ Complete | 2025-03 |
| `docs/components/librechat.md` | ✅ Complete | 2025-03 |
| `docs/components/swag.md` | ✅ Complete | 2025-03 |
| `docs/components/authelia.md` | ✅ Complete | 2025-03 |
| `docs/components/perplexica.md` | ✅ Complete | 2025-03 |
| `docs/components/dockhand.md` | ✅ Complete | 2025-03 |
| `docs/components/open-notebook.md` | ✅ Complete | 2025-03 |
| `docker/swag/` | ✅ Complete | 2025-03 |
| `docker/authelia/` | ✅ Complete | 2025-03 |
| `docker/perplexica/` | ✅ Complete | 2025-03 |
| `docker/dockhand/` | ✅ Complete | 2025-03 |
| `docker/open-notebook/` | ✅ Complete | 2025-03 |
| `docker/librechat/` | ✅ Complete | 2025-03 |
| `docker/firecrawl-simple/` | ✅ Complete | 2025-03 |
| `docker/reranker/` | ✅ Complete | 2025-03 |
| `docs/architecture.md` | 🔲 Planned | — |
| `docs/getting-started.md` | 🔲 Planned | — |
| `docs/components/swag-authelia.md` | ✅ Split into `swag.md` + `authelia.md` | 2025-03 |
| `docs/components/qmd.md` | 🔲 Planned | — |
| `docs/components/memsearch.md` | 🔲 Planned | — |
| `docs/components/memory-sync.md` | 🔲 Planned | — |
| `scripts/` | 🔲 Planned | — |

## Cross-Reference: Components → Documents

| Component | Docs | Config | Compose |
|-----------|------|--------|---------|
| LibreChat | [`docs/components/librechat.md`](docs/components/librechat.md) | `docker/librechat/librechat.yaml.example` | `docker/librechat/docker-compose.yml` |
| firecrawl-simple | [`docs/components/librechat.md`](docs/components/librechat.md) (§Web Search Pipeline) | — | `docker/firecrawl-simple/docker-compose.yml` |
| Reranker | [`docs/components/librechat.md`](docs/components/librechat.md) (§Rerank) | — | `docker/reranker/docker-compose.yml` |
| SWAG | [`docs/components/swag.md`](docs/components/swag.md) | — | `docker/swag/docker-compose.yml` |
| Authelia | [`docs/components/authelia.md`](docs/components/authelia.md) | — | `docker/authelia/docker-compose.yml` |
| qmd | [`mcp-servers/README.md`](mcp-servers/README.md) (§qmd) | — | (host-level service) |
| Perplexica + SearXNG | [`docs/components/perplexica.md`](docs/components/perplexica.md) | — | `docker/perplexica/docker-compose.yml` |
| Dockhand | [`docs/components/dockhand.md`](docs/components/dockhand.md) | — | `docker/dockhand/docker-compose.yml` |
| Open Notebook | [`docs/components/open-notebook.md`](docs/components/open-notebook.md) | — | `docker/open-notebook/docker-compose.yml` |
| MCP servers (all) | [`mcp-servers/README.md`](mcp-servers/README.md) | Config patterns inline | — |
| PM2 services | [`pm2/ecosystem.config.js.example`](pm2/ecosystem.config.js.example) | Inline | — |
| CLAUDE.md hierarchy | [`claude-code/CLAUDE.md.example`](claude-code/CLAUDE.md.example), [`claude-code/projects/`](claude-code/projects/) | — | — |
