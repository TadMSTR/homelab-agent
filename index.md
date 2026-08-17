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
│   ├── components/              # Per-service operational reference (99 docs)
│   │   ├── foundation/          # Host, reverse proxy, auth, secrets, backups (10)
│   │   ├── observability/       # Grafana, Loki, SigNoz, Langfuse, exporters (13)
│   │   ├── ai-search/           # Ollama, SearXNG, Firecrawl, Reranker (10)
│   │   ├── memory/              # Memory architecture, Milvus, memsearch, Graphiti (9)
│   │   ├── agent/               # scoped-mcp, Matrix, NATS, task queue, agent-bus (16)
│   │   ├── apps/                # Nextcloud, Plane, Vikunja, tools stack (8)
│   │   ├── mcp-servers/         # system-ops, githost, dockhand, patchmon, pm2 (12)
│   │   ├── cicd/                # Woodpecker, Temporal, Renovate, CloudCLI (7)
│   │   └── platform/            # Doc health, disk probes, drift detection (9)
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
| `docs/components/foundation/forge-configs.md` | Host configuration management |
| `docs/components/foundation/backrest.md` | Backup solution |
| `docs/components/foundation/btrbk-daily.md` | Btrfs snapshots |
| `docs/components/foundation/btrfs-scrub-monthly.md` | Btrfs maintenance |
| `docs/components/foundation/vault-seal-watcher.md` | Vault seal monitoring |
| `docs/operations/appdata-layout.md` | /opt/appdata directory structure |

### Layer 2 — Docker Service Stack

**Reverse proxy / Auth:**

| Doc | Topic |
|-----|-------|
| `docs/components/foundation/swag.md` | SWAG nginx reverse proxy, SSL |
| `docs/components/foundation/authentik.md` | SSO, forward auth, OIDC |
| `docs/components/foundation/vaultwarden.md` | Password manager |
| `docs/components/foundation/vault.md` | Secret management |

**Observability:**

| Doc | Topic |
|-----|-------|
| `docs/components/observability/grafana-alloy.md` | Grafana, Loki, Alloy |
| `docs/components/observability/grafana-dashboards.md` | Dashboard inventory |
| `docs/components/observability/grafana-image-renderer.md` | Grafana image renderer |
| `docs/components/observability/influxdb.md` | Time-series metrics |
| `docs/components/observability/telegraf.md` | Metrics collection |
| `docs/components/observability/prometheus.md` | Prometheus scraping |
| `docs/components/observability/signoz.md` | APM + distributed tracing |
| `docs/components/observability/langfuse.md` | LLM observability |
| `docs/components/observability/nvidia-exporter.md` | GPU metrics export |

**AI & Search:**

| Doc | Topic |
|-----|-------|
| `docs/components/ai-search/ollama.md` | Local LLM inference |
| `docs/components/ai-search/ollama-queue-proxy.md` | Queuing/auth layer in front of Ollama |
| `docs/components/ai-search/open-webui.md` | Multi-model chat UI |
| `docs/components/ai-search/searxng.md` | Private meta-search |
| `docs/components/ai-search/firecrawl.md` | Web extraction |
| `docs/components/ai-search/crawl4ai.md` | Web crawling |
| `docs/components/ai-search/reranker.md` | ML reranking |
| `docs/components/ai-search/hister.md` | Browser semantic search |
| `docs/components/ai-search/kiwix.md` | Offline Wikipedia/SO/Arch Wiki |

**Memory & Knowledge:**

| Doc | Topic |
|-----|-------|
| `docs/components/memory/memory-architecture.md` | Full memory system overview |
| `docs/components/memory/memory-stack.md` | Milvus + OpenSearch |
| `docs/components/memory/memory-services.md` | PM2 indexing services and promotion pipeline |
| `docs/components/memory/memsearch.md` | Hybrid vector+BM25 search library |
| `docs/components/memory/memsearch-mcp.md` | memsearch MCP server (:8493) |
| `docs/components/memory/memsearch-summarize.md` | Session transcript summarizer |
| `docs/components/memory/memory-expire.md` | Expired note eviction |
| `docs/components/memory/graphiti.md` | Knowledge graph |

**Agent Infrastructure:**

| Doc | Topic |
|-----|-------|
| `docs/components/agent/synapse.md` | Matrix homeserver |
| `docs/components/agent/nats.md` | Event bus |
| `docs/components/agent/dragonfly.md` | Agent state backend |
| `docs/components/foundation/dockhand.md` | Docker stack management UI |
| `docs/components/cicd/code-server.md` | VS Code in the browser |
| `docs/components/cicd/owners-manual.md` | Auto-generated platform reference (MkDocs) |

**CI/CD & Workflow:**

| Doc | Topic |
|-----|-------|
| `docs/components/cicd/woodpecker.md` | Woodpecker CI |
| `docs/components/cicd/temporal.md` | Workflow engine |
| `docs/components/cicd/renovate.md` | Dependency updates |
| `docs/components/cicd/patchmon.md` | Apt patch management |
| `docs/components/cicd/cloudcli.md` | Browser Claude Code UI |

**Apps:**

| Doc | Topic |
|-----|-------|
| `docs/components/apps/nextcloud.md` | Nextcloud file/collaboration suite |
| `docs/components/apps/plane.md` | Plane project/issue tracking app stack |
| `docs/components/apps/proton-bridge.md` | Proton Mail IMAP/SMTP bridge |
| `docs/components/apps/vikunja.md` | Vikunja task/project management app |
| `docs/components/apps/stunnel.md` | TLS tunnel for Proton Bridge |
| `docs/components/apps/tools-stack.md` | 8-tool browser utilities stack |
| `docs/components/apps/librechat.md` | LibreChat multi-model chat platform |
| `docs/components/apps/homepage.md` | Homepage dashboard + Docker socket proxy sidecar |

### Layer 3 — Multi-Agent Engine

**Agent platform:**

| Doc | Topic |
|-----|-------|
| `docs/components/agent/scoped-mcp.md` | Per-agent MCP proxy, manifest schema, Phase 7 hardening |
| `docs/components/agent/agent-bus.md` | Inter-agent event log, HMAC signing, NATS federation |
| `docs/components/agent/task-queue-mcp.md` | Task queue MCP server |
| `docs/components/agent/task-queue-widget.md` | Task queue dashboard widget (React, Matrix) |
| `docs/components/agent/task-dispatcher.md` | Task routing and headless agent launch |
| `docs/components/agent/pool-manager.md` | Ephemeral agent session pre-warming |
| `docs/components/agent/matrix-dispatcher.md` | Matrix dispatch loop |
| `docs/components/agent/matrix-mcp.md` | Matrix send/receive MCP |
| `docs/components/agent/matrix-admin-bot.md` | Matrix room admin bot |
| `docs/components/agent/matrix-task-queue-bot.md` | Matrix task queue notification bot |
| `docs/components/agent/matrix-hitl-bot.md` | Matrix HITL approval bot (scoped-mcp in-session approvals) |
| `docs/components/agent/nats-mcp.md` | NATS publish/subscribe MCP |
| `docs/components/agent/harlock.md` | Harlock personal agent |
| `manifests/` | Sanitized agent manifest examples |
| `claude-code/` | Claude Code project configs |

**MCP servers — infrastructure:**

| Doc | Topic |
|-----|-------|
| `docs/components/mcp-servers/system-ops.md` | File, directory, and command MCP |
| `docs/components/mcp-servers/githost-mcp.md` | Git + GitHub/Gitea/GitLab MCP |
| `docs/components/mcp-servers/dockhand-mcp.md` | Docker container/stack management MCP |
| `docs/components/mcp-servers/patchmon-mcp.md` | Apt patch management MCP |
| `docs/components/mcp-servers/pm2-mcp.md` | PM2 process management MCP |
| `docs/components/mcp-servers/code-server-mcp.md` | code-server management MCP |
| `docs/components/mcp-servers/plane-mcp.md` | Plane issue tracking MCP |
| `docs/components/mcp-servers/vikunja-mcp.md` | Vikunja task tracking MCP |
| `docs/components/mcp-servers/doc-cache-mcp.md` | Documentation cache MCP |
| `docs/components/mcp-servers/datastore-mcp.md` | Multi-backend datastore query MCP |
| `docs/components/mcp-servers/librechat-mcp.md` | LibreChat agent-management MCP |
| `docs/components/mcp-servers/backrest-mcp.md` | Backrest backup management MCP |
| `docs/components/nextcloud-mcp.md` | Nextcloud file/calendar/notes MCP |
| `docs/components/jobsearch-mcp.md` | Job search tracking MCP |

**MCP servers — observability:**

| Doc | Topic |
|-----|-------|
| `docs/components/observability/grafana-mcp.md` | Grafana query MCP |
| `docs/components/observability/signoz-mcp.md` | APM trace/metric query MCP |
| `docs/components/observability/langfuse-mcp.md` | LLM trace query MCP |
| `docs/components/observability/loki-mcp.md` | Loki log query MCP |

**MCP servers — search & knowledge:**

| Doc | Topic |
|-----|-------|
| `docs/components/ai-search/searxng-mcp.md` | Web search + fetch cascade MCP |
| `docs/components/memory/memsearch-mcp.md` | Hybrid memory search MCP |

**Memory system:**

| Doc | Topic |
|-----|-------|
| `docs/components/memory/memory-architecture.md` | Three-tier memory system overview |
| `docs/components/memory/memsearch.md` | Hybrid memory search library |

**Monitoring probes (PM2 cron jobs):**

| Doc | Topic |
|-----|-------|
| `docs/components/platform/doc-health.md` | Documentation audit system |
| `docs/components/platform/doc-sync-daily.md` | Daily doc sync cron |
| `docs/components/platform/disk-space-probe.md` | Disk usage monitoring + alerts |
| `docs/components/platform/snapshot-monitoring.md` | Btrfs snapshot space monitoring (bloat + capacity probes, retention) |
| `docs/components/platform/writer-doc-queue.md` | Writer task-queue cron (headless doc drafting) |
| `docs/components/platform/drift-detector-scan.md` | Config drift detection |
| `docs/components/platform/build-unblock-scan.md` | Stalled build detection |
| `docs/components/platform/git-drift-alert.md` | Uncommitted git drift alerting |
| `docs/components/platform/git-remote-cred-check.md` | Plaintext credentials in git remote URLs |
| `docs/components/memory/memory-compact-qc.md` | Weekly QC on `memsearch compact` output |
| `docs/components/dep-update-check.md` | Dependency update scanner |
| `docs/components/forge-reboot-gate.md` | Reboot-required gate check |
| `docs/components/venv-deploy.md` | Python venv deployment pattern |
| `docs/operations/runbooks.md` | Operational runbooks |

## By Task

### "I want to understand the overall architecture"
→ Read `README.md`, then `AGENTS.md`, then the relevant `docs/components/<category>/` docs

### "I want to deploy a specific service"
→ `docs/components/<category>/<service>.md`, then `docker/<service>/`

### "I want to set up the agent system"
→ `docs/components/agent/scoped-mcp.md`, then `manifests/`, then `claude-code/`

### "I want to understand the memory system"
→ `docs/components/memory/memory-architecture.md`, then `docs/components/memory/memory-services.md`

### "I want to see the full build history"
→ `CHANGELOG.md` — phase build records live in Gitea `host-forge/phases`, not in this public repo (ADR-0003)

### "I want to replicate the monitoring stack"
→ `docker/observability/`, `docs/components/observability/grafana-alloy.md`, `docs/components/observability/influxdb.md`

### "I want to understand how agents communicate"
→ `docs/components/agent/nats.md`, `docs/components/agent/agent-bus.md`, `docs/components/agent/matrix-dispatcher.md`

### "I want to understand how tasks are routed"
→ `docs/components/agent/task-queue-mcp.md`, `docs/components/agent/task-dispatcher.md`

### "I want to run a diagnostic or recovery procedure"
→ `docs/operations/runbooks.md`

## Component Inventory

Key cross-references:

| Component | Depends On | Used By |
|-----------|-----------|---------|
| `scoped-mcp` | All MCP servers | All agents |
| `memsearch-mcp` | Milvus, Reranker | All agents |
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
