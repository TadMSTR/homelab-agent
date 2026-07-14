# Infrastructure MCP Servers

General-purpose MCP servers that give agents access to host and platform operations: file I/O, git, Docker management, package management, and issue tracking. These are the "hands" agents use to interact with forge infrastructure.

Domain-specific MCP servers (observability, memory, search) live in their respective subdirectories.

## Servers

| Doc | Server | What It Wraps | Available To |
|-----|--------|--------------|-------------|
| [system-ops.md](system-ops.md) | system-ops | File, directory, and command execution | sysadmin, developer, writer |
| [githost-mcp.md](githost-mcp.md) | githost-mcp | Git + GitHub / Gitea / GitLab (32 tools) | All agents |
| [dockhand-mcp.md](dockhand-mcp.md) | dockhand-mcp | Docker container and stack management | sysadmin |
| [patchmon-mcp.md](patchmon-mcp.md) | patchmon-mcp | Apt patch management | sysadmin |
| [pm2-mcp.md](pm2-mcp.md) | pm2-mcp | PM2 process management | sysadmin |
| [code-server-mcp.md](code-server-mcp.md) | code-server-mcp | code-server session management | developer |
| [plane-mcp.md](plane-mcp.md) | plane-mcp | Plane issue tracking | All agents |
| [datastore-mcp.md](datastore-mcp.md) | datastore-mcp | Read-only queries across 8 database backends | not yet wired |
| [librechat-mcp.md](librechat-mcp.md) | librechat-mcp | LibreChat agent management (CRUD) | not yet wired |
| [vikunja-mcp.md](vikunja-mcp.md) | vikunja-mcp | Vikunja task/project management (71 tools, token passthrough) | All agents |

## Access Control

All servers are accessed through [scoped-mcp](../agent/scoped-mcp.md). Each agent's manifest defines which servers it can reach, with per-tool denylists, rate limits, and argument filters applied at the proxy level.
