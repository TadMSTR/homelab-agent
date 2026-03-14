# homelab-ops MCP

homelab-ops is a FastMCP (Python) server that provides shell execution, filesystem operations, and process inspection over HTTP. It's the primary tool server for Claude Code and LibreChat agents — the HTTP equivalent of Desktop Commander, designed for clients that can't use stdio transport.

It sits in [Layer 1](../../README.md#layer-1--host--core-tooling) of the architecture as core tooling. Every agent session that reads files, runs commands, or inspects processes goes through homelab-ops.

## Why a Custom MCP Server

Desktop Commander works well for Claude Desktop (stdio transport), but Claude Code and LibreChat need HTTP. Rather than running multiple Desktop Commander instances or proxying stdio, homelab-ops exposes exactly the tools needed as a single shared HTTP service. Multiple clients connect to the same running instance — no subprocess management, no port conflicts.

The FastMCP framework keeps the codebase small. The entire server is a single Python file with six tool definitions.

## Tools

| Tool | Description |
|------|-------------|
| `run_command` | Execute a shell command, returns stdout/stderr/exit_code. Optional cwd and timeout. |
| `read_file` | Read a file by absolute path. Optional start/end line range for large files. |
| `write_file` | Write or overwrite a file. Creates parent directories automatically. |
| `edit_file` | Find-and-replace edit — old string must match exactly once in the file. |
| `read_directory` | List directory contents. Optional recursive mode with configurable max depth. |
| `list_processes` | List running processes sorted by CPU, memory, or PID. Optional name filter. |

## Runtime

- **PM2 service:** `homelab-ops-mcp` (always-on)
- **Port:** 8282 (streamable-HTTP)
- **Endpoint:** `http://localhost:8282/mcp`
- **Dependencies:** `fastmcp`, `psutil`

LibreChat containers reach it via `host.docker.internal:8282`. Claude Code connects directly to `localhost:8282`.

## Configuration

Claude Code `settings.json`:
```json
{
  "homelab-ops": {
    "type": "url",
    "url": "http://localhost:8282/mcp"
  }
}
```

LibreChat `librechat.yaml` MCP entry:
```yaml
- url: "http://host.docker.internal:8282/mcp"
  type: "streamable-http"
```

## Security Considerations

homelab-ops runs as the host user with full shell access. There is no built-in authentication — any client that can reach port 8282 can execute commands. This is acceptable because:

- The port is bound to localhost for Claude Code connections
- LibreChat containers reach it via Docker's `host.docker.internal` bridge
- SWAG does not proxy this port externally
- The host firewall blocks external access to 8282

If you expose homelab-ops beyond localhost, add authentication or restrict access at the network level.

## Relationship to Desktop Commander

Both cover the same surface area — shell, files, processes. The difference is transport:

| | Desktop Commander | homelab-ops |
|---|---|---|
| Transport | stdio | HTTP (streamable) |
| Client | Claude Desktop only | Claude Code, LibreChat, any HTTP MCP client |
| Lifecycle | Launched per-session by Claude Desktop | Always-on PM2 service |
| Multi-client | No (subprocess per client) | Yes (shared instance) |

You can run both. Claude Desktop uses Desktop Commander via stdio; Claude Code and LibreChat use homelab-ops via HTTP. They don't conflict.

## Related Docs

- [MCP Servers README](../../mcp-servers/README.md#homelab-ops) — full tool reference and config patterns
- [Agent Panel](agent-panel.md) — uses homelab-ops for diagnostics and file operations
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — service definition
