# Grafana Dashboards

Custom Grafana dashboards deployed on forge for monitoring agent infrastructure and
supporting services. All dashboards are accessible at `grafana.helmforge.me` (Authentik
OIDC auth).

## SearXNG-MCP Operations

Operational dashboard for the searxng-mcp server, covering search and fetch performance,
cache behavior, and error tracking.

**Datasources:**

| Source | Type | What it provides |
|--------|------|------------------|
| SigNoz ClickHouse | Traces/metrics | Search/fetch latency, tool call counts, error rates |
| scoped-mcp traces | Distributed traces | End-to-end request flow through the MCP proxy layer |
| Loki | Logs | Error log panels (filtered to searxng-mcp) |
| Dragonfly (searxng-dragonfly) | Redis metrics | Cache hit/miss ratio, key count, memory usage |

**Key panels:**
- Search request volume and latency (p50/p95/p99)
- Fetch tier cascade breakdown (Kiwix / Hister / direct / Wayback)
- Cache hit rate over time
- Error log stream (Loki)

## Redis/Dragonfly/Valkey Fleet

Health monitoring dashboard for all 7 Redis-compatible instances running on forge.

**Datasources:**

| Source | Type | What it provides |
|--------|------|------------------|
| Grafana Redis datasource | Direct connection | Per-instance metrics via `grafana-datasources` network |

**Monitored instances:**

| Instance | Stack | Purpose |
|----------|-------|---------|
| `searxng-dragonfly` | searxng | searxng-mcp cache + SearXNG result cache |
| `agent-dragonfly` | agent-platform | Agent session state, HITL gate |
| `langfuse-dragonfly` | langfuse | Langfuse application cache |
| `firecrawl-redis` | firecrawl | Firecrawl job queue |
| `oqp-valkey` | agent-platform | Ollama queue proxy embedding cache |
| `patchmon-valkey` | patchmon | PatchMon cache |
| `plane-valkey` | plane | Plane project management cache |

**Key panels:**
- Connected clients per instance
- Memory usage and fragmentation ratio
- Commands processed per second
- Key count and eviction rate
- Instance availability (up/down)

## Infrastructure

- **Grafana container:** `grafana` in observability stack, port 3003
- **Network:** `grafana-datasources` bridge connects Grafana to all Redis instances and SigNoz ClickHouse
- **Dashboard provisioning:** Managed via Grafana UI (not file-provisioned)
- **Auth:** All Redis instances use `requirepass` (or `DFLY_requirepass` for Dragonfly)

## Operations

```bash
# Check Grafana health
curl -s http://127.0.0.1:3003/api/health | jq .

# List dashboards via API
curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://127.0.0.1:3003/api/search?type=dash-db | jq '.[].title'

# View dashboard in browser
# https://grafana.helmforge.me
```

## Dependencies

- SigNoz ClickHouse (traces/metrics backend)
- Loki (log aggregation)
- All 7 Redis-compatible instances (via `grafana-datasources` network)
- `grafana-datasources` Docker network must include both Grafana and target containers
