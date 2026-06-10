# pm2-mcp

pm2-mcp is a FastMCP Python server that wraps the PM2 process manager, giving forge
agents structured read and limited write access to PM2 services with typed responses.
It speaks directly to `pm2 jlist`, eliminating the need for raw shell access or output
scraping.

- **Package:** `pm2-mcp` v0.3.0 (TadMSTR/pm2-mcp)
- **Repo:** `/home/ted/repos/personal/pm2-mcp/`
- **Transport:** streamable-http — `127.0.0.1:8486`
- **Runtime:** Python 3.10+

## Tools

| Tool | Type | Description |
|------|------|-------------|
| `list_services` | read | List all PM2 processes with status, uptime, CPU, memory |
| `get_service` | read | Detailed info for a single PM2 process by name |
| `get_logs` | read | Recent log lines for a process |
| `get_status` | read | Quick status summary (online/stopped/errored) |
| `restart_service` | write | Restart a PM2 process by name |
| `stop_service` | write | Stop a PM2 process |
| `start_service` | write | Start a stopped PM2 process |
| `reload_service` | write | Graceful reload of a PM2 process |
| `flush_logs` | write | Flush PM2 log files |
| `save` | write | Save current PM2 process list |

Write operations validate service names against the live PM2 process list before
executing; unrecognized names return `{ok: false}` without touching PM2.

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `MCP_HOST` | No | `127.0.0.1` | Bind address |
| `MCP_PORT` | No | `8486` | Listen port |
| `PYTHONUNBUFFERED` | No | `1` | Prevent output buffering (set in PM2 config) |

## Dependencies

- Python 3.10+ with `fastmcp>=3.2.4,<4`
- PM2 installed and available in PATH

## Launch

PM2 process named `pm2-mcp`, configured via `ecosystem.config.js` in the repo root.
Fork mode (no clustering).

## scoped-mcp Wiring

| Manifest | Access |
|----------|--------|
| `sysadmin-agent.yml` | Full (read + write). Write tools HITL-gated. Rate limits: `stop_service` 5/min, `restart_service` 10/min |
| `research-agent.yml` | Read-only. Denylisted: `start_service`, `stop_service`, `restart_service`, `reload_service`, `flush_logs`, `save` |
| `developer-agent.yml` | No access |
| `security-agent.yml` | No access |
| `writer-agent.yml` | No access |

## Security Notes

- Binds to localhost only — no external network exposure
- No authentication required (intentional for local agent use)
- Write operations validate process names against live PM2 list before executing
- Sysadmin write access is HITL-gated via scoped-mcp approval flow
