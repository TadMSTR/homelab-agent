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
│   └── diagrams/                # Architecture diagrams (drawio/svg)
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
| `docs/components/vault-seal-watcher.md` | Vault seal monitoring |
| `docs/operations/appdata-layout.md` | /opt/appdata directory structure |

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
| `docs/components/grafana-dashboards.md` | Dashboard inventory |
| `docs/components/grafana-image-renderer.md` | Grafana image renderer |
| `docs/components/influxdb.md` | Time-series metrics |
| `docs/components/telegraf.md` | Metrics collection |
| `docs/components/prometheus.md` | Prometheus scraping |
| `docs/components/signoz.md` | APM + distributed tracing |
| `docs/components/langfuse.md` | LLM observability |
| `docs/components/nvidia-exporter.md` | GPU metrics export |

**AI & Search:**

| Doc | Topic |
|-----|-------|
| `docs/components/ollama.md` | Local LLM inference |
| `docs/components/ollama-queue-proxy.md` | Queuing/auth layer in front of Ollama |
| `docs/components/open-webui.md` | Multi-model chat UI |
| `docs/components/searxng.md` | Private meta-search |
| `docs/components/firecrawl.md` | Web extraction |
| `docs/components/crawl4ai.md` | Web crawling |
| `docs/components/reranker.md` | ML reranking |
| `docs/components/hister.md` | Browser semantic search |
| `docs/components/kiwix.md` | Offline Wikipedia/SO/Arch Wiki |

**Memory & Knowledge:**

| Doc | Topic |
|-----|-------|
| `docs/components/memory-stack.md` | Milvus + OpenSearch |
| `docs/components/graphiti.md` | Knowledge graph |
| `docs/components/memory-architecture.md` | Full memory system overview |
| `docs/components/memory-services.md` | PM2 indexing services and promotion pipeline |
| `docs/components/memsearch-summarize.md` | Session transcript summarizer |
| `docs/components/memory-expire.md` | Expired note eviction |

**Agent Infrastructure:**

| Doc | Topic |
|-----|-------|
| `docs/components/synapse.md` | Matrix homeserver |
| `docs/components/nats.md` | Event bus |
| `docs/components/dragonfly.md` | Agent state backend |
| `docs/components/dockhand.md` | Docker stack management UI |
| `docs/components/code-server.md` | VS Code in the browser |
| `docs/components/owners-manual.md` | Auto-generated platform reference (MkDocs) |

**CI/CD & Workflow:**

| Doc | Topic |
|-----|-------|
| `docs/components/woodpecker.md` | Woodpecker CI |
| `docs/components/temporal.md` | Workflow engine |
| `docs/components/renovate.md` | Dependency updates |
| `docs/components/patchmon.md` | Apt patch management |

### Layer 3 — Multi-Agent Engine

**Agent platform:**

| Doc | Topic |
|-----|-------|
| `docs/components/scoped-mcp.md` | Per-agent MCP proxy, manifest schema, Phase 7 hardening |
| `docs/components/agent-bus.md` | Inter-agent event log, HMAC signing, NATS federation |
| `docs/components/task-queue-mcp.md` | Task queue MCP server |
| `docs/components/task-dispatcher.md` | Task routing and headless agent launch |
| `docs/components/pool-manager.md` | Ephemeral agent session pre-warming |
| `docs/components/matrix-dispatcher.md` | Matrix dispatch loop |
| `docs/components/matrix-admin-bot.md` | Matrix room admin bot |
| `manifests/` | Sanitized agent manifest examples |
| `claude-code/` | Claude Code project configs |

**MCP servers — search & web:**

| Doc | Topic |
|-----|-------|
| `docs/components/searxng-mcp.md` | Web search + fetch cascade MCP |

**MCP servers — infrastructure:**

| Doc | Topic |
|-----|-------|
| `docs/components/system-ops.md` | File, directory, and command MCP |
| `docs/components/githost-mcp.md` | Git + GitHub/Gitea/GitLab MCP |
| `docs/components/dockhand-mcp.md` | Docker container/stack management MCP |
| `docs/components/patchmon-mcp.md` | Apt patch management MCP |
| `docs/components/pm2-mcp.md` | PM2 process management MCP |
| `docs/components/loki-mcp.md` | Loki log query MCP |
| `docs/components/grafana-mcp.md` | Grafana query MCP |
| `docs/components/nats-mcp.md` | NATS publish/subscribe MCP |
| `docs/components/code-server-mcp.md` | code-server management MCP |

**MCP servers — knowledge & comms:**

| Doc | Topic |
|-----|-------|
| `docs/components/matrix-mcp.md` | Matrix send/receive MCP |
| `docs/components/langfuse-mcp.md` | LLM trace query MCP |
| `docs/components/signoz-mcp.md` | APM trace/metric query MCP |
| `docs/components/plane-mcp.md` | Plane issue tracking MCP |
| `docs/components/memsearch-mcp.md` | Hybrid memory search MCP |

**Memory system:**

| Doc | Topic |
|-----|-------|
| `docs/components/memory-architecture.md` | Three-tier memory system overview |
| `docs/components/memsearch.md` | Hybrid memory search library |

**Documentation & monitoring:**

| Doc | Topic |
|-----|-------|
| `docs/components/doc-health.md` | Documentation audit system |
| `docs/operations/runbooks.md` | Operational runbooks |

### Monitoring Probes (PM2 cron jobs)

| Doc | Topic |
|-----|-------|
| `docs/components/disk-space-probe.md` | Disk usage monitoring + alerts |
| `docs/components/snapshot-space-probe.md` | Btrfs snapshot space monitoring |
| `docs/components/nvidia-exporter.md` | GPU metrics to InfluxDB |
| `docs/components/drift-detector-scan.md` | Config drift detection |
| `docs/components/doc-sync-daily.md` | Daily doc sync cron |
| `docs/components/build-unblock-scan.md` | Stalled build detection |
| `docs/components/git-drift-alert.md` | Uncommitted git drift alerting |

## By Task

### "I want to understand the overall architecture"
→ Read `README.md`, then `docs/phases/` in order

### "I want to deploy a specific service"
→ `docs/components/<service>.md`, then `docker/<service>/`

### "I want to set up the agent system"
→ `docs/components/scoped-mcp.md`, then `manifests/`, then `claude-code/`

### "I want to understand the memory system"
→ `docs/components/memory-architecture.md`, then `docs/components/memory-services.md`

### "I want to see the full build history"
→ `docs/phases/` — each phase doc covers what was added and what security findings were resolved

### "I want to replicate the monitoring stack"
→ `docker/observability/`, `docs/components/grafana-alloy.md`, `docs/components/influxdb.md`

### "I want to understand how agents communicate"
→ `docs/components/nats.md`, `docs/components/agent-bus.md`, `docs/components/matrix-dispatcher.md`

### "I want to understand how tasks are routed"
→ `docs/components/task-queue-mcp.md`, `docs/components/task-dispatcher.md`

### "I want to run a diagnostic or recovery procedure"
→ `docs/operations/runbooks.md`

## Component Inventory

Key cross-references:

| Component | Depends On | Used By |
|-----------|-----------|---------|
| `scoped-mcp` | All MCP servers | All agents |
| `memsearch-mcp` | Milvus, OpenSearch, Reranker | All agents |
| `matrix-dispatcher` | Synapse | All agents |
| `matrix-mcp` | Synapse | All agents |
| `agent-bus` | NATS | All agents |
| `qmd` | File system | All agents |
| `task-queue-mcp` | DragonflyDB | All agents (cross-agent handoffs) |
| `task-dispatcher` | task-queue-mcp, scoped-mcp | Platform (headless launches) |
| `graphiti` | Neo4j | research, sysadmin |
| `system-ops` | Host OS | sysadmin, developer, writer |
| `githost-mcp` | Gitea, GitHub | All agents |
| `searxng-mcp` | SearXNG, Firecrawl, Reranker | All agents |
| `dockhand-mcp` | Docker socket | sysadmin |
| `patchmon-mcp` | apt | sysadmin |
