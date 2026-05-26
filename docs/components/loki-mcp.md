# loki-mcp

loki-mcp is a read-only FastMCP server that exposes Loki log queries as MCP tools. Agents call it to search and tail logs from any labeled stream — application logs, PM2 output, system events — using LogQL without needing direct Loki API access.

**Repo:** `TadMSTR/loki-mcp`  
**Deploy path:** `~/repos/personal/loki-mcp/`  
**Transport:** stdio (PM2 process — no port binding)  
**Version:** v0.1.0

## Why

Claude Code agents need log access for diagnosis and audit work, but direct Loki API calls require LogQL fluency and HTTP auth handling from inside an agent context. loki-mcp wraps the Loki HTTP API in a typed MCP interface: agents describe what they want in plain terms (stream selector, time window, pattern) and get structured results back. Being read-only, it carries no write risk.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `query_logs` | Run a LogQL log query over a time range, return matching lines |
| `query_aggregate` | Run a LogQL metric query (rate, count_over_time, sum by label) |
| `get_labels` | List all label names in the Loki instance |
| `get_label_values` | List values for a specific label (e.g., all values of `{job}`) |
| `get_streams` | List available log streams (label combinations with recent data) |
| `tail_recent` | Fetch the N most recent lines from a stream without a time window |

All tools are read-only. No write or delete operations are exposed.

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `LOKI_URL` | `http://localhost:3100` | Base URL of the Loki instance |

No authentication is required — loki-mcp is intended for internal use on a host with local Loki access. If your Loki instance requires auth, add it to `LOKI_URL` or extend the implementation.

## PM2 Setup

loki-mcp runs as a stdio PM2 process alongside other MCP servers:

```bash
pm2 start ecosystem.config.js --only loki-mcp
```

The ecosystem entry uses `interpreter: "python3"` and sets `LOKI_URL` via `env`. Logs go to `~/.pm2/logs/loki-mcp-*.log`.

## Usage Examples

```python
# Fetch the 50 most recent lines from the agent-bus process
tail_recent(stream='{job="agent-bus"}', limit=50)

# Search for errors in a time window
query_logs(
    query='{job="homelab-ops"} |= "ERROR"',
    start="2026-05-26T00:00:00Z",
    end="2026-05-26T23:59:59Z"
)

# Count error rate by job over the last hour
query_aggregate(
    query='sum by (job) (rate({job=~".+"} |= "ERROR" [5m]))',
    start="now-1h",
    end="now"
)
```

## Prerequisites

Loki's HTTP port (default 3100) must be reachable from the host running loki-mcp. If Loki runs in a Docker stack on the same host, ensure the port is published to `localhost` or that the container network is accessible.

## Gotchas and Lessons Learned

**LogQL stream selectors are required.** Loki rejects queries without at least one label matcher (e.g., `{job="..."}` or `{job=~".+"}`). Bare pattern searches without a stream selector will error.

**Time ranges must use RFC3339 or Loki's relative syntax.** `query_logs` and `query_aggregate` accept either ISO timestamps (`2026-05-26T00:00:00Z`) or Loki relative notation (`now-1h`). Plain integers (Unix nanoseconds) also work if needed.

**`tail_recent` is not a live tail.** It fetches the N most recent lines at call time — it doesn't stream. For continuous monitoring, call it on a polling schedule or use `query_logs` with a sliding window.
