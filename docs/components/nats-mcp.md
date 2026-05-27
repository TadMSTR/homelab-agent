# nats-mcp

nats-mcp is a read-only FastMCP server that exposes NATS messaging bus health as MCP tools. Agents call it to inspect server stats, active connections, subscriptions, and JetStream state without needing direct access to the NATS monitoring port.

**Repo:** `TadMSTR/nats-mcp`  
**Deploy path:** `~/repos/personal/nats-mcp/`  
**Transport:** stdio (PM2 process — no port binding)  
**Version:** v0.1.0

## Why

NATS is the agent event bus. When diagnosing agent communication issues — dropped events, slow consumers, JetStream pressure — the NATS monitoring API has the answers. nats-mcp makes that data available to Claude Code agents as typed MCP tools so they can correlate NATS health with task queue state without manual `curl` calls or port forwarding.

## MCP Tools

| Tool | Purpose |
|------|---------|
| `get_server_stats` | Server version, uptime, connection count, message rates, memory, CPU |
| `get_connections` | Active connections with subscription and message counts (capped at 500) |
| `get_subscription_stats` | Subscription counts, cache hit rate, fanout stats |
| `get_jetstream_status` | JetStream streams, consumers, message counts, bytes, API stats |
| `get_health` | Health check — `ok` or error with detail |

All tools are read-only. No publish, subscribe, or admin operations are exposed.

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `NATS_MONITOR_URL` | `http://localhost:8222` | Base URL of the NATS monitoring port |

No authentication is required — the NATS monitoring port is unauthenticated by design. Access control is handled at the network level.

## PM2 Setup

nats-mcp runs as a stdio PM2 process alongside other MCP servers:

```bash
pm2 start ecosystem.config.js --only nats-mcp
```

The ecosystem entry uses `interpreter: "python3"` and sets `NATS_MONITOR_URL` via `env`. Logs go to `~/.pm2/logs/nats-mcp-*.log`.

## Usage Examples

```python
# Check server health and uptime
get_health()

# Get current connection count and message rates
get_server_stats()

# Inspect JetStream streams and consumer lag
get_jetstream_status()

# List active connections (capped at 500)
get_connections(limit=100)
```

## Prerequisites

NATS's HTTP monitoring port (default 8222) must be published and reachable from the host running nats-mcp. This is typically enabled in the NATS server config with `http_port: 8222` or via `--http_port 8222`.

## Gotchas and Lessons Learned

**`get_connections` is capped at 500.** The NATS monitoring API can return thousands of connections on a busy server. nats-mcp clamps the result to 500 to avoid overwhelming the agent context. If you need more, paginate manually via the raw API.

**`server_id` is stripped from all responses.** The NATS monitoring API includes a `server_id` field (a random string) in most responses. It is stripped by nats-mcp because it changes across restarts and adds noise without diagnostic value.

**JetStream must be enabled on the server.** `get_jetstream_status` returns an error if the NATS server was started without JetStream. Enable it with `jetstream: true` in the server config or `--jetstream` flag.

**Monitoring port vs client port.** The NATS monitoring port (8222) is separate from the client port (4222). Only the monitoring port is needed for nats-mcp. Do not point `NATS_MONITOR_URL` at the client port.
