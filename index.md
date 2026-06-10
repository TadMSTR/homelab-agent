# homelab-agent — Document Index

Machine-readable navigation index for the homelab-agent platform repository. Load only the sections relevant to your task — don't load everything at once.

## Repo Map

```
homelab-agent/
├── README.md                    # Architecture overview, hardware, component tables
├── AGENTS.md                    # Agent roster, scoped-mcp architecture, key docs
├── CHANGELOG.md                 # Build history
├── index.md                     # THIS FILE — navigation index
├── docs/
│   ├── components/              # Per-service operational reference (76 docs)
│   ├── phases/                  # Build history docs (23 phases)
│   ├── operations/              # Runbooks and operational procedures
│   └── diagrams/                # Architecture diagrams
├── docker/                      # Docker Compose stacks + .env.example templates
├── scripts/                     # Maintenance and monitoring scripts
├── manifests/                   # Sanitized agent manifest examples
├── claude-code/                 # Claude Code project configs per agent
├── pm2/                         # PM2 ecosystem config and process docs
└── mcp-servers/                 # MCP server index and architecture overview
```

## By Layer

### Layer 1 — Host

| Doc | Topic |
|-----|-------|
| `README.md` | Hardware specs, OS, storage layout |
| `docs/components/forge-configs.md` | Host configuration management |
| `docs/components/backrest.md` | Backup solution |
| `docs/components/btrbk-daily.md` | Btrfs snapshots |
| `docs/components/btrfs-scrub-monthly.md` | Btrfs maintenance |

### Layer 2 — Docker Service Stack

**Reverse proxy / Auth:**

| Doc | Topic |
|-----|-------|
| `docs/components/swag.md` | SWAG nginx reverse proxy, SSL |
| `docs/components/authentik.md` | SSO, forward auth, OIDC |
| `docs/components/vaultwarden.md` | Password manager |
| `docs/components/vault.md` | Secret management |

**Observability:**

| Doc | Topic |
|-----|-------|
| `docs/components/grafana-alloy.md` | Grafana, Loki, Alloy |
| `docs/components/influxdb.md` | Time-series metrics |
| `docs/components/telegraf.md` | Metrics collection |
| `docs/components/prometheus.md` | Prometheus scraping |
| `docs/components/signoz.md` | APM + distributed tracing |
| `docs/components/langfuse.md` | LLM observability |

**AI & Search:**

| Doc | Topic |
|-----|-------|
| `docs/components/ollama.md` | Local LLM inference |
| `docs/components/open-webui.md` | Multi-model chat UI |
| `docs/components/searxng.md` | Private meta-search |
| `docs/components/firecrawl.md` | Web extraction |
| `docs/components/crawl4ai.md` | Web crawling |
| `docs/components/reranker.md` | ML reranking |
| `docs/components/hister.md` | Browser semantic search |

**Memory & Knowledge:**

| Doc | Topic |
|-----|-------|
| `docs/components/memory-stack.md` | Milvus + OpenSearch |
| `docs/components/graphiti.md` | Knowledge graph |
| `docs/components/memory-architecture.md` | Full memory system overview |

**Agent Infrastructure:**

| Doc | Topic |
|-----|-------|
| `docs/components/synapse.md` | Matrix homeserver |
| `docs/components/nats.md` | Event bus |
| `docs/components/task-queue-mcp.md` | Task queue |
| `docs/components/cloudcli.md` | Browser Claude Code UI |
| `docs/components/dragonfly.md` | Agent state backend |

**CI/CD & Workflow:**

| Doc | Topic |
|-----|-------|
| `docs/components/woodpecker.md` | Woodpecker CI |
| `docs/components/temporal.md` | Workflow engine |
| `docs/components/renovate.md` | Dependency updates |
| `docs/components/patchmon.md` | Apt patch management |

### Layer 3 — Multi-Agent Engine

| Doc | Topic |
|-----|-------|
| `docs/components/scoped-mcp.md` | scoped-mcp architecture, manifest schema |
| `docs/components/matrix-dispatcher.md` | Matrix dispatch loop |
| `docs/components/agent-bus.md` | Inter-agent event log |
| `docs/components/memory-architecture.md` | Three-tier memory system |
| `docs/components/memsearch.md` | Hybrid memory search |
| `docs/components/memsearch-mcp.md` | memsearch MCP server |
| `manifests/` | Sanitized agent manifest examples |
| `claude-code/` | Claude Code project configs |

## By Task

### "I want to understand the overall architecture"
→ Read `README.md`, then `docs/phases/` in order

### "I want to deploy a specific service"
→ `docs/components/<service>.md`, then `docker/<service>/`

### "I want to set up the agent system"
→ `docs/components/scoped-mcp.md`, then `manifests/`, then `claude-code/`

### "I want to understand the memory system"
→ `docs/components/memory-architecture.md`

### "I want to see the full build history"
→ `docs/phases/` — each phase doc covers what was added and what security findings were resolved

### "I want to replicate the monitoring stack"
→ `docker/observability/`, `docs/components/grafana-alloy.md`, `docs/components/influxdb.md`

### "I want to understand how agents communicate"
→ `docs/components/nats.md`, `docs/components/agent-bus.md`, `docs/components/matrix-dispatcher.md`

## Component Inventory

See `docs/components/` for the full list. Key cross-references:

| Component | Depends On | Used By |
|-----------|-----------|---------|
| scoped-mcp | All MCP servers | All agents |
| memsearch-mcp | Milvus, OpenSearch, Reranker | All agents |
| matrix-dispatcher | Synapse | All agents |
| agent-bus | NATS | All agents |
| qmd | File system | All agents |
| task-queue-mcp | DragonflyDB | All agents (cross-agent handoffs) |
| graphiti | Neo4j | research, sysadmin |
| system-ops | Host OS | sysadmin, developer, writer |
| githost-mcp | Gitea, GitHub | All agents |
