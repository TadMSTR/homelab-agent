# matrix-mcp (forge)

The forge instance of matrix-mcp gives forge's operator agents Matrix messaging capability
via the `helmforge.me` homeserver. It is a separate PM2 process from the claudebox
`matrix-mcp` instance — different homeserver, different bot account, different port.

- **Source:** `~/repos/personal/matrix-mcp/`
- **PM2 name:** `matrix-mcp` (ID 20)
- **Transport:** HTTP (FastMCP), `127.0.0.1:8487`
- **Status:** online

## How It Runs

```
fastmcp run server.py --transport http --host 127.0.0.1 --port 8487
```

Launched by PM2 from `~/repos/personal/matrix-mcp/` using the virtualenv at
`venv/bin/fastmcp`. Logs at `~/.pm2/logs/matrix-mcp-{out,error}.log`.

Credentials are sourced from the forge secrets file referenced in `server.py`. The bot
account on the forge homeserver sends and receives on behalf of forge agents.

## Scoped-MCP Registration

All 5 forge operator agent scoped-mcp configs include `matrix-mcp` as a module:

```json
{
  "type": "mcp_proxy",
  "name": "matrix-mcp",
  "url": "http://localhost:8487/mcp"
}
```

This gives each forge agent the same `mcp__matrix__*` tool surface available to claudebox
agents, but routed through the forge homeserver. The endpoint is localhost-only — not
accessible from other hosts on forge-net.

## Tools

Same tool surface as the claudebox matrix-mcp:

| Tool | What it does |
|------|-------------|
| `send_matrix_message` | Send text or markdown to a room by short name |
| `post_artifact` | Upload a file and post a formatted link to the room |
| `get_matrix_messages` | Fetch recent messages from a room |
| `list_matrix_rooms` | List all rooms the bot account is joined to |

## Related Docs

- [synapse.md](synapse.md) — forge homeserver
- [matrix-dispatcher.md](matrix-dispatcher.md) — message routing to forge agents
- [scoped-mcp.md](scoped-mcp.md) — per-agent tool proxy that includes this MCP
