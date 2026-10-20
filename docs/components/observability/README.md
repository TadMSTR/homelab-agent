# Observability — Metrics, Logs & Traces

Monitoring, logging, and tracing for the entire platform. Three stacks cover different concerns: Grafana+Loki+Alloy for dashboards and logs, SigNoz for APM and distributed traces, and Langfuse for LLM-specific observability.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [grafana-alloy.md](grafana-alloy.md) | Grafana + Loki + Alloy stack, Loki tenancy | 3000 (Grafana), 3100 (Loki) |
| [alloy-relay.md](alloy-relay.md) | Ingest relay for remote host Loki pushes | 3500 (internal) |
| [grafana-dashboards.md](grafana-dashboards.md) | Dashboard inventory and management | — |
| [grafana-image-renderer.md](grafana-image-renderer.md) | Grafana image renderer sidecar | 8081 |
| [grafana-mcp.md](grafana-mcp.md) | Grafana query MCP server | 8489 |
| [influxdb.md](influxdb.md) | Time-series metrics (InfluxDB 3) | 8086 |
| [telegraf.md](telegraf.md) | Host and Docker metrics collection | — |
| [prometheus.md](prometheus.md) | Prometheus scraping | 9090 |
| [signoz.md](signoz.md) | APM + distributed tracing | 3301 |
| [signoz-mcp.md](signoz-mcp.md) | SigNoz query MCP server | 8488 |
| [langfuse.md](langfuse.md) | LLM observability — traces, costs, scores | 3005 |
| [langfuse-mcp.md](langfuse-mcp.md) | Langfuse query MCP server | 8486 |
| [loki-mcp.md](loki-mcp.md) | Loki log query MCP server | 8485 |
| [nvidia-exporter.md](nvidia-exporter.md) | GPU metrics exporter | 9835 |
| [healthchecks.md](healthchecks.md) | Cron job liveness (Healthchecks, own stack) | 8509 (loopback) |

## MCP Servers

Four MCP servers give agents query access to observability data:

- **grafana-mcp** — dashboard and panel queries
- **signoz-mcp** — APM traces, logs, and metrics
- **langfuse-mcp** — LLM trace and score queries
- **loki-mcp** — log queries via LogQL
