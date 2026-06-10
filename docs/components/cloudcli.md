# CloudCLI

CloudCLI is a web-based Claude Code interface for forge. It provides a browser UI for
running Claude Code sessions, exploring files, managing git repos, and accessing a shell
terminal — without needing an SSH connection to the forge host.

- **PM2 name:** `cloudcli` (id 16)
- **URL:** `cloudcli.helmforge.me`
- **Port:** `3001` (SWAG-proxied)

## How It Runs

```bash
cloudcli start --port 3001
```

Launched via PM2 using `~/scripts/cloudcli.sh`. CloudCLI is a globally installed npm
package on forge.

## Features

| Feature | Notes |
|---------|-------|
| Claude Code sessions | Launch and interact with `claude` in the browser |
| File explorer | Browse and edit files on the forge filesystem |
| Git integration | View diffs, stage, commit from the UI |
| Shell terminal | Full interactive terminal |
| MCP management | View registered MCP servers and their status |

## SWAG Routing

`cloudcli.subdomain.conf` proxies `cloudcli.helmforge.me` to `localhost:3001`. CloudCLI
uses WebSockets for terminal and session streaming — the proxy conf enables WebSocket
upgrade headers.

## Access

CloudCLI is proxied through SWAG and accessible at `cloudcli.helmforge.me`. Access
control is at the SWAG level.

## Related Docs

- [swag.md](swag.md) — HTTPS reverse proxy
- [scoped-mcp.md](scoped-mcp.md) — per-agent MCP tool proxy used in Claude Code sessions
