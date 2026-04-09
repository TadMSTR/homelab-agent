# pm2-mcp

pm2-mcp is a FastMCP server that wraps the PM2 CLI, giving agents structured read and limited write access to PM2 services on claudebox. It speaks directly to `pm2 jlist` for structured JSON output rather than scraping human-readable text.

It sits in [Layer 1](../../README.md#layer-1--host--core-tooling) alongside homelab-ops-mcp. Where homelab-ops-mcp provides general shell access, pm2-mcp provides typed, safe tool calls specifically scoped to PM2 — no raw shell needed to check service health, tail logs, or restart a hung process.

- **Source:** `~/repos/personal/pm2-mcp/server.py`
- **Transport:** streamable-http (localhost only)
- **Port:** 8486
- **PM2 service:** id 26 (`pm2-mcp`)

## Why a Dedicated PM2 Server

homelab-ops-mcp's `run_command` can already call `pm2` — so why a separate server?

The difference is structure. `run_command` returns raw text that the agent has to parse. pm2-mcp returns typed dicts: `uptime_ms`, `memory_mb`, `restarts`, `status` — fields an agent can reason about directly without a parsing step. It also validates service names before issuing write operations (restart/stop/start), avoiding silent failures when a name is misspelled.

For agents doing health checks or operational responses, pm2-mcp is the right tool. For one-off `pm2` commands that don't fit the tool surface, homelab-ops-mcp is still available.

## Tools

### Read

| Tool | Description |
|------|-------------|
| `list_services` | List all PM2 services with key fields. Optional `status_filter`: `"online"`, `"stopped"`, or `"errored"`. |
| `get_service` | Full detail for one service by name: script path, cwd, args, log files, created_at, plus all summary fields. |
| `get_logs` | Tail recent log output for a service. `lines` defaults to 50; `include_errors` defaults to `true`. |

### Write

| Tool | Description |
|------|-------------|
| `restart_service` | Restart a running or errored service. Returns `{ok: true}` or `{ok: false, error: ...}`. |
| `stop_service` | Stop a service. Does not remove it from the PM2 process list. |
| `start_service` | Resume a stopped service already registered in PM2. Does not register a new process. |

### `list_services` response shape

```json
[
  {
    "name": "task-dispatcher",
    "pm_id": 12,
    "status": "online",
    "pid": 18432,
    "uptime_ms": 3720000,
    "restarts": 0,
    "cpu_pct": 0.2,
    "memory_mb": 48.5,
    "exec_mode": "fork_mode"
  }
]
```

## Runtime

- **PM2 service:** `pm2-mcp` (id 25, always-on)
- **Endpoint:** `http://127.0.0.1:8486/mcp`
- **Bind:** localhost only — not reachable from Docker containers or external hosts
- **User:** `ted` (UID 1000) — same user as the PM2 daemon, so `pm2 jlist` sees all services

## Configuration

Claude Code CLI reads MCP servers from `~/.claude.json` (not `settings.json`):

```json
{
  "mcpServers": {
    "pm2": {
      "type": "http",
      "url": "http://127.0.0.1:8486/mcp"
    }
  }
}
```

Note: use `"type": "http"` not `"type": "streamable-http"` in `~/.claude.json`, and bind to `127.0.0.1` explicitly — `localhost` resolves to IPv6 (`::1`) first on Debian, which will fail silently.

pm2-mcp is **not** wired into LibreChat — it's localhost-only and there's no use case for LibreChat agents managing claudebox PM2 services directly.

## Security Considerations

pm2-mcp binds to `127.0.0.1` only. Any client that can reach port 8486 can restart or stop services — the write tools have no confirmation step. This is acceptable because:

- Localhost-only binding; no external or Docker access
- Only Claude Code agents (running as `ted`) connect to it
- Write tools validate service names and return structured errors rather than running blind

The `start_service` tool resumes registered services only — it cannot register arbitrary new processes. There is no `delete` or `flush` tool exposure.

## Gotchas and Lessons Learned

**`start_service` ≠ registering a new process.** It calls `pm2 start <name>` on an already-registered service. To register a new PM2 process, use homelab-ops-mcp's `run_command` with the appropriate `pm2 start` invocation.

**`get_logs` output format.** PM2 interleaves stdout and stderr in its log file even when you ask for one stream. The `include_errors` parameter controls whether the stderr log path is also read — it doesn't filter the stdout log file itself.

**`uptime_ms` is 0 for non-online services.** The uptime calculation only runs when `status == "online"`. A stopped or errored service always returns `uptime_ms: 0`.

**Runs as a PM2 process itself.** pm2-mcp is managed by the same PM2 daemon it talks to. `list_services` will always include the `pm2-mcp` entry (id 25) in its output.

## Related Docs

- [homelab-ops-mcp](homelab-ops-mcp.md) — general shell and filesystem access; use for PM2 operations outside pm2-mcp's tool surface
