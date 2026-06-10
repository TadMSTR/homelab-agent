# docs/components

Per-service operational reference for the homelab-agent platform. 76 docs covering every service, MCP server, and background job running on forge.

Each doc covers: what the service is, where it runs, configuration, dependencies, how to restart/check health/view logs, and scoped-mcp integration where applicable.

---

## Host & Backups

| Doc | Service |
|-----|---------|
| `forge-configs.md` | Host configuration management (version-controlled configs + Vault secrets merge) |
| `backrest.md` | Backup scheduler (restic, NFS target) |
| `btrbk-daily.md` | Btrfs snapshot scheduler |
| `btrfs-scrub-monthly.md` | Btrfs filesystem maintenance |
| `vault-seal-watcher.md` | Vault seal monitor (polls health endpoint, Matrix alert) |

## Reverse Proxy & Auth

| Doc | Service |
|-----|---------|
| `swag.md` | SWAG nginx reverse proxy, wildcard SSL |
| `authentik.md` | SSO, forward auth, OIDC provider |
| `vaultwarden.md` | Password manager (Bitwarden-compatible) |
| `vault.md` | Secret management, AppRole auth, transit engine |

## Observability

| Doc | Service |
|-----|---------|
| `grafana-alloy.md` | Grafana, Loki, Alloy stack |
| `grafana-dashboards.md` | Dashboard inventory and management |
| `grafana-image-renderer.md` | Grafana image renderer sidecar |
| `grafana-mcp.md` | Grafana query MCP server |
| `influxdb.md` | Time-series metrics (InfluxDB 3) |
| `telegraf.md` | Host and Docker metrics collection |
| `prometheus.md` | Prometheus scraping |
| `signoz.md` | APM + distributed tracing (ClickHouse backend) |
| `signoz-mcp.md` | SigNoz query MCP server |
| `langfuse.md` | LLM observability (traces, scores, datasets) |
| `langfuse-mcp.md` | Langfuse query MCP server |
| `loki-mcp.md` | Loki log query MCP server |
| `nvidia-exporter.md` | GPU metrics exporter |

## AI & Search

| Doc | Service |
|-----|---------|
| `ollama.md` | Local LLM inference |
| `ollama-queue-proxy.md` | Queuing, auth, and routing layer in front of Ollama |
| `open-webui.md` | Multi-model chat UI |
| `searxng.md` | Private meta-search engine |
| `searxng-mcp.md` | Web search + fetch cascade MCP server |
| `firecrawl.md` | JS-rendered web extraction |
| `crawl4ai.md` | Web crawling |
| `reranker.md` | ML result reranking |
| `hister.md` | Browser history semantic search |
| `kiwix.md` | Offline Wikipedia / Stack Overflow / Arch Wiki |

## Memory & Knowledge

| Doc | Service |
|-----|---------|
| `memory-architecture.md` | **Start here** — full three-tier memory system overview with diagrams |
| `memory-stack.md` | Milvus + OpenSearch Docker stack |
| `memory-services.md` | PM2 indexing services and promotion pipeline |
| `memsearch.md` | Hybrid vector+BM25 search library |
| `memsearch-mcp.md` | memsearch MCP server (:8493) |
| `memsearch-summarize.md` | Session transcript summarizer (Anthropic API) |
| `memory-expire.md` | Expired note eviction cron |
| `graphiti.md` | Temporal knowledge graph (Neo4j backend) |

## Agent Infrastructure

| Doc | Service |
|-----|---------|
| `synapse.md` | Matrix homeserver |
| `matrix-mcp.md` | Matrix send/receive MCP server |
| `matrix-dispatcher.md` | Matrix-to-agent task dispatch loop |
| `matrix-admin-bot.md` | Matrix room administration bot |
| `matrix-task-queue-bot.md` | Matrix task queue notification bot |
| `nats.md` | NATS JetStream event bus |
| `nats-mcp.md` | NATS publish/subscribe MCP server |
| `agent-bus.md` | Inter-agent event log, HMAC signing, NATS federation |
| `task-queue-mcp.md` | Task queue MCP server |
| `task-dispatcher.md` | Task routing and headless agent session launcher |
| `pool-manager.md` | Ephemeral agent session directory pre-warming |
| `dragonfly.md` | Agent state backend (Redis-compatible) |
| `scoped-mcp.md` | Per-agent MCP proxy — manifest schema, Phase 7 hardening, Vault integration |

## Infrastructure MCP Servers

| Doc | Service |
|-----|---------|
| `system-ops.md` | File, directory, and command execution MCP |
| `githost-mcp.md` | Git + GitHub / Gitea / GitLab MCP (32 tools) |
| `dockhand-mcp.md` | Docker container and stack management MCP |
| `patchmon-mcp.md` | Apt patch management MCP |
| `pm2-mcp.md` | PM2 process management MCP |
| `code-server-mcp.md` | code-server management MCP |
| `plane-mcp.md` | Plane issue tracking MCP |
| `dockhand.md` | Dockhand web UI (Docker stack management) |

## CI/CD & Dev Tools

| Doc | Service |
|-----|---------|
| `woodpecker.md` | Woodpecker CI |
| `temporal.md` | Temporal workflow engine |
| `renovate.md` | Automated dependency updates |
| `patchmon.md` | Apt patch tracking and approval |
| `code-server.md` | VS Code in the browser |
| `cloudcli.md` | Browser Claude Code UI |
| `owners-manual.md` | Auto-generated platform reference (MkDocs site) |

## Documentation & Health

| Doc | Service |
|-----|---------|
| `doc-health.md` | Documentation audit system (weekly full scan + nightly targeted) |
| `doc-sync-daily.md` | Daily documentation sync cron |

## Monitoring Probes (PM2 cron jobs)

| Doc | Service |
|-----|---------|
| `disk-space-probe.md` | Disk usage monitoring + Matrix alerts |
| `snapshot-space-probe.md` | Btrfs snapshot space monitoring |
| `drift-detector-scan.md` | Configuration drift detection |
| `build-unblock-scan.md` | Stalled build detection |
| `git-drift-alert.md` | Uncommitted git change alerting |
