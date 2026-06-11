# nats-mcp

nats-mcp is a read-only FastMCP server that wraps the NATS HTTP monitoring API, giving the
sysadmin agent visibility into NATS server health, connections, subscriptions, and JetStream
status without requiring NATS credentials.

- **Package:** `nats-mcp` v0.1.1 (TadMSTR/nats-mcp)
- **Repo:** `/home/ted/repos/personal/nats-mcp/`
- **Venv:** `/home/ted/repos/personal/nats-mcp/.venv/`
- **Transport:** stdio (launched via `run-nats-mcp.sh`)
- **NATS Monitor URL:** `http://localhost:8222` (monitoring port, bound to 127.0.0.1 only)
- **Auth:** None — NATS monitoring port requires no credentials
- **Log:** `/opt/appdata/nats-mcp/logs/nats-mcp.log` (JSON, structlog)

## Installation

```bash
cd /home/ted/repos/personal
git clone https://github.com/TadMSTR/nats-mcp.git
cd nats-mcp
python3 -m venv .venv
.venv/bin/pip install -e .
```

## Launch Script

`/home/ted/scripts/run-nats-mcp.sh` (bash — no credentials needed):

```bash
#!/bin/bash
set -euo pipefail
export NATS_MONITOR_URL="http://localhost:8222"
exec /home/ted/repos/personal/nats-mcp/.venv/bin/python3 -m nats_mcp.server
```

## Tools (5, all read-only)

| Tool | Description |
|------|-------------|
| `get_server_stats` | Server version, uptime, connection count, message rates, memory/CPU |
| `get_connections` | Active connections with subscription and message counts (max 500) |
| `get_subscription_stats` | Subscription counts, cache hit rate, fanout stats |
| `get_jetstream_status` | JetStream streams, consumers, messages, bytes, API stats |
| `get_health` | Health check — ok or error |

No publish, subscribe, or admin endpoints are exposed. `server_id` stripped from all
responses to reduce noise. `get_connections` limit is typed as `int` and clamped to 500.

## scoped-mcp Wiring

Added to the sysadmin agent config at `/opt/agents/sysadmin/config/scoped-mcp.json.legacy`:

```json
{
    "type": "mcp_proxy",
    "name": "nats-mcp",
    "command": "/home/ted/scripts/run-nats-mcp.sh"
}
```

Only the sysadmin agent has access.

## Observability

Structured JSON logs written to `/opt/appdata/nats-mcp/logs/nats-mcp.log` via structlog.
Log level controlled by `LOG_LEVEL` env var (default: INFO). OTEL tracing available opt-in
via `OTEL_EXPORTER_OTLP_ENDPOINT`.

## Security Notes

- No credentials required or stored — NATS monitoring port is unauthenticated by design
- NATS monitoring port (8222) is bound to `127.0.0.1` only — not reachable from LAN
- Security audit: `forge-observer-mcps-deploy` — 2 Low findings (both in signoz-mcp, not nats-mcp), remediation-complete 2026-05-27
