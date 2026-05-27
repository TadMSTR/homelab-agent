# signoz-mcp

signoz-mcp is a read-only FastMCP server that exposes SigNoz observability data as MCP tools. Agents call it to query services, traces, logs, metrics, and alert rules without needing direct SigNoz API access or knowledge of its HTTP query format.

**Repo:** `TadMSTR/signoz-mcp`  
**Deploy path:** `~/repos/personal/signoz-mcp/`  
**Transport:** stdio (PM2 process — no port binding)  
**Version:** v0.1.0

## Why

Claude Code agents doing sysadmin and diagnostic work need observability data: which services are erroring, what traces show, what the alert state is. The SigNoz HTTP API is versioned (v3/v5), uses a custom query DSL, and requires API key auth — friction points that don't belong in an agent prompt. signoz-mcp wraps all of that in typed MCP tools with plain arguments. Being read-only, it carries no write risk.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `list_services` | All services with RED metrics (rate, errors, duration) |
| `count_errors` | Error span count grouped by service over a time range |
| `search_traces` | Filter traces by service, error state, minimum duration |
| `tail_logs` | Recent logs for a service filtered by severity |
| `count_log_errors` | Error/warn log rate over time |
| `query_metric` | Named metric with optional label filter |
| `list_metrics` | All ingested metric names |
| `list_alert_rules` | Alert rules and current firing state |
| `get_health` | Connectivity and API key check |

All tools are read-only. No write or delete operations are exposed.

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `SIGNOZ_URL` | `http://localhost:8080` | Base URL of the SigNoz instance |
| `SIGNOZ_API_KEY` | — | **Required.** SigNoz Service Account token |
| `SIGNOZ_QUERY_VERSION` | `v3` | Query API version — `v3` or `v5` |

`SIGNOZ_API_KEY` must be a SigNoz Service Account token. Create one at **Settings → Integrations → Service Accounts** in the SigNoz UI.

`SIGNOZ_QUERY_VERSION` is validated at module load. If the value is not `v3` or `v5`, the server refuses to start rather than silently sending malformed queries.

## PM2 Setup

signoz-mcp runs as a stdio PM2 process alongside other MCP servers:

```bash
pm2 start ecosystem.config.js --only signoz-mcp
```

The ecosystem entry uses `interpreter: "python3"` and sets `SIGNOZ_URL`, `SIGNOZ_API_KEY`, and `SIGNOZ_QUERY_VERSION` via `env`. Logs go to `~/.pm2/logs/signoz-mcp-*.log`.

## Usage Examples

```python
# Check which services are active
list_services()

# Find error spikes in the last hour
count_errors(start="now-1h", end="now")

# Search for slow traces in a specific service
search_traces(service="my-api", min_duration_ms=500)

# Tail recent error logs
tail_logs(service="my-api", severity="ERROR", limit=50)

# Query a specific metric
query_metric(metric="system_cpu_usage", label_filter='host="myhost"')
```

## Prerequisites

SigNoz's HTTP API port (default 8080) must be reachable from the host running signoz-mcp. A valid Service Account token is required — signoz-mcp will fail at startup if `SIGNOZ_API_KEY` is unset.

## Gotchas and Lessons Learned

**Service names and severity values are allowlisted.** `tail_logs` and related tools validate service names (alphanumeric, dash, underscore, dot) and severity values (`TRACE`/`DEBUG`/`INFO`/`WARN`/`ERROR`/`FATAL`) before sending requests. Unrecognized values return a validation error rather than a malformed API call.

**`query_metric` label_filter is unsanitized by design.** This parameter accepts arbitrary label selectors for complex metric queries (e.g., `host="myhost",env="prod"`). It is a power-user field documented as an accepted risk — use with trusted input only.

**Response size caps are enforced.** All list/query tools cap result counts to avoid returning unbounded payloads to the agent context. Adjust limits in the tool arguments if you need more results.

**Query version mismatch.** If your SigNoz instance uses a different query API version, set `SIGNOZ_QUERY_VERSION=v5`. The default `v3` is confirmed working on SigNoz v0.118.x. Mismatched versions surface as API errors, not silent wrong results.
