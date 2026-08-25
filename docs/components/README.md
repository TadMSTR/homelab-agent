# docs/components

Per-service operational reference for the homelab-agent platform. 80 docs covering every service, MCP server, and background job running on forge, organized into 9 categories.

Each doc covers: what the service is, where it runs, configuration, dependencies, how to restart/check health/view logs, and scoped-mcp integration where applicable.

---

## [`foundation/`](foundation/) — Host, Networking & Auth (10)

| Doc | Service |
|-----|---------|
| [`forge-configs.md`](foundation/forge-configs.md) | Host configuration management (version-controlled configs + Vault secrets merge) |
| [`backrest.md`](foundation/backrest.md) | Backup scheduler (restic, NFS target) |
| [`btrbk-daily.md`](foundation/btrbk-daily.md) | Btrfs snapshot scheduler |
| [`btrfs-scrub-monthly.md`](foundation/btrfs-scrub-monthly.md) | Btrfs filesystem maintenance |
| [`vault-seal-watcher.md`](foundation/vault-seal-watcher.md) | Vault seal monitor (polls health endpoint, Matrix alert) |
| [`swag.md`](foundation/swag.md) | SWAG nginx reverse proxy, wildcard SSL |
| [`authentik.md`](foundation/authentik.md) | SSO, forward auth, OIDC provider |
| [`vaultwarden.md`](foundation/vaultwarden.md) | Password manager (Bitwarden-compatible) |
| [`vault.md`](foundation/vault.md) | Secret management, AppRole auth, transit engine |
| [`dockhand.md`](foundation/dockhand.md) | Docker stack manager UI |

## [`observability/`](observability/) — Metrics, Logs & Traces (13)

| Doc | Service |
|-----|---------|
| [`grafana-alloy.md`](observability/grafana-alloy.md) | Grafana, Loki, Alloy stack |
| [`grafana-dashboards.md`](observability/grafana-dashboards.md) | Dashboard inventory and management |
| [`grafana-image-renderer.md`](observability/grafana-image-renderer.md) | Grafana image renderer sidecar |
| [`grafana-mcp.md`](observability/grafana-mcp.md) | Grafana query MCP server |
| [`influxdb.md`](observability/influxdb.md) | Time-series metrics (InfluxDB 3) |
| [`telegraf.md`](observability/telegraf.md) | Host and Docker metrics collection |
| [`prometheus.md`](observability/prometheus.md) | Prometheus scraping |
| [`signoz.md`](observability/signoz.md) | APM + distributed tracing (ClickHouse backend) |
| [`signoz-mcp.md`](observability/signoz-mcp.md) | SigNoz query MCP server |
| [`langfuse.md`](observability/langfuse.md) | LLM observability (traces, scores, datasets) |
| [`langfuse-mcp.md`](observability/langfuse-mcp.md) | Langfuse query MCP server |
| [`loki-mcp.md`](observability/loki-mcp.md) | Loki log query MCP server |
| [`nvidia-exporter.md`](observability/nvidia-exporter.md) | GPU metrics exporter |

## [`ai-search/`](ai-search/) — AI Inference & Search (10)

| Doc | Service |
|-----|---------|
| [`ollama.md`](ai-search/ollama.md) | Local LLM inference |
| [`ollama-queue-proxy.md`](ai-search/ollama-queue-proxy.md) | Queuing, auth, and routing layer in front of Ollama |
| [`open-webui.md`](ai-search/open-webui.md) | Multi-model chat UI |
| [`searxng.md`](ai-search/searxng.md) | Private meta-search engine |
| [`searxng-mcp.md`](ai-search/searxng-mcp.md) | Web search + fetch cascade MCP server |
| [`firecrawl.md`](ai-search/firecrawl.md) | JS-rendered web extraction |
| [`crawl4ai.md`](ai-search/crawl4ai.md) | Web crawling |
| [`reranker.md`](ai-search/reranker.md) | ML result reranking |
| [`hister.md`](ai-search/hister.md) | Browser history semantic search |
| [`kiwix.md`](ai-search/kiwix.md) | Offline Wikipedia / Stack Overflow / Arch Wiki |

## [`memory/`](memory/) — Memory & Knowledge Graph (8)

| Doc | Service |
|-----|---------|
| [`memory-architecture.md`](memory/memory-architecture.md) | **Start here** — full three-tier memory system overview with diagrams |
| [`memory-stack.md`](memory/memory-stack.md) | Milvus + OpenSearch Docker stack |
| [`memory-services.md`](memory/memory-services.md) | PM2 indexing services and promotion pipeline |
| [`memsearch.md`](memory/memsearch.md) | Hybrid vector+BM25 search library |
| [`memsearch-mcp.md`](memory/memsearch-mcp.md) | memsearch MCP server (:8493) |
| [`memsearch-summarize.md`](memory/memsearch-summarize.md) | Session transcript summarizer (Anthropic API) |
| [`memory-expire.md`](memory/memory-expire.md) | Expired note eviction cron |
| [`graphiti.md`](memory/graphiti.md) | Temporal knowledge graph (Neo4j backend), retired 2026-08-05 |

## [`agent/`](agent/) — Agent Infrastructure (14)

| Doc | Service |
|-----|---------|
| [`scoped-mcp.md`](agent/scoped-mcp.md) | Per-agent MCP proxy — manifest schema, Phase 7 hardening, Vault integration |
| [`agent-bus.md`](agent/agent-bus.md) | Inter-agent event log, HMAC signing, NATS federation |
| [`task-queue-mcp.md`](agent/task-queue-mcp.md) | Task queue MCP server |
| [`task-queue-widget.md`](agent/task-queue-widget.md) | Task queue dashboard widget (React, embedded in Matrix) |
| [`task-dispatcher.md`](agent/task-dispatcher.md) | Task routing and headless agent session launcher |
| [`pool-manager.md`](agent/pool-manager.md) | Ephemeral agent session directory pre-warming |
| [`synapse.md`](agent/synapse.md) | Matrix homeserver |
| [`matrix-mcp.md`](agent/matrix-mcp.md) | Matrix send/receive MCP server |
| [`matrix-dispatcher.md`](agent/matrix-dispatcher.md) | Matrix-to-agent task dispatch loop |
| [`matrix-admin-bot.md`](agent/matrix-admin-bot.md) | Matrix room administration bot |
| [`matrix-task-queue-bot.md`](agent/matrix-task-queue-bot.md) | Matrix task queue notification bot |
| [`nats.md`](agent/nats.md) | NATS JetStream event bus |
| [`nats-mcp.md`](agent/nats-mcp.md) | NATS publish/subscribe MCP server |
| [`dragonfly.md`](agent/dragonfly.md) | Agent state backend (Redis-compatible) |

## [`mcp-servers/`](mcp-servers/) — Infrastructure MCP Servers (8)

| Doc | Service |
|-----|---------|
| [`system-ops.md`](mcp-servers/system-ops.md) | File, directory, and command execution MCP |
| [`githost-mcp.md`](mcp-servers/githost-mcp.md) | Git + GitHub / Gitea / GitLab MCP (32 tools) |
| [`dockhand-mcp.md`](mcp-servers/dockhand-mcp.md) | Docker container and stack management MCP |
| [`patchmon-mcp.md`](mcp-servers/patchmon-mcp.md) | Apt patch management MCP |
| [`pm2-mcp.md`](mcp-servers/pm2-mcp.md) | PM2 process management MCP |
| [`code-server-mcp.md`](mcp-servers/code-server-mcp.md) | code-server management MCP |
| [`plane-mcp.md`](mcp-servers/plane-mcp.md) | Plane issue tracking MCP |
| [`backrest-mcp.md`](mcp-servers/backrest-mcp.md) | Backup plan status, snapshots, restore MCP (Backrest) |

## [`cicd/`](cicd/) — CI/CD & Dev Tools (7)

| Doc | Service |
|-----|---------|
| [`woodpecker.md`](cicd/woodpecker.md) | Woodpecker CI |
| [`temporal.md`](cicd/temporal.md) | Temporal workflow engine |
| [`renovate.md`](cicd/renovate.md) | Automated dependency updates |
| [`patchmon.md`](cicd/patchmon.md) | Apt patch tracking and approval |
| [`code-server.md`](cicd/code-server.md) | VS Code in the browser |
| [`cloudcli.md`](cicd/cloudcli.md) | Browser Claude Code UI |
| [`owners-manual.md`](cicd/owners-manual.md) | Auto-generated platform reference (MkDocs site) |

## [`platform/`](platform/) — Monitoring & Doc Health (7)

| Doc | Service |
|-----|---------|
| [`doc-health.md`](platform/doc-health.md) | Documentation audit system (weekly full scan + nightly targeted) |
| [`doc-sync-daily.md`](platform/doc-sync-daily.md) | Daily documentation sync cron |
| [`disk-space-probe.md`](platform/disk-space-probe.md) | Disk usage monitoring + Matrix alerts |
| [`snapshot-monitoring.md`](platform/snapshot-monitoring.md) | Btrfs snapshot capacity + bloat monitoring |
| [`drift-detector-scan.md`](platform/drift-detector-scan.md) | Configuration drift detection |
| [`build-unblock-scan.md`](platform/build-unblock-scan.md) | Stalled build detection |
| [`git-drift-alert.md`](platform/git-drift-alert.md) | Uncommitted git change alerting |

## [`apps/`](apps/) — Productivity & Self-Hosted Services (5)

| Doc | Service |
|-----|---------|
| [`nextcloud.md`](apps/nextcloud.md) | File sync, collaboration suite |
| [`librechat.md`](apps/librechat.md) | Self-hosted multi-provider AI chat web app |
| [`proton-bridge.md`](apps/proton-bridge.md) | Proton Mail SMTP relay (native) |
| [`stunnel.md`](apps/stunnel.md) | TLS wrapper for Proton Mail Bridge |
| [`tools-stack.md`](apps/tools-stack.md) | 8 stateless browser utilities (PDF, diagrams, dev tools, image edit) |
