# Infrastructure MCP Servers

General-purpose MCP servers that give agents access to host and platform operations: file I/O, git, Docker management, process management, and issue tracking. These are the "hands" agents use to interact with forge infrastructure.

Domain-specific MCP servers (observability, memory, search) live in their respective subdirectories.

## Servers

| Doc | Server | What It Wraps | Available To |
|-----|--------|--------------|-------------|
| [system-ops.md](system-ops.md) | system-ops | File, directory, and command execution | sysadmin, developer, writer |
| [githost-mcp.md](githost-mcp.md) | githost-mcp | Git + GitHub / Gitea / GitLab (74 tools) | developer, sysadmin, security, research, writer, fleet, harlock, steward |
| [dockhand-mcp.md](dockhand-mcp.md) | dockhand-mcp | Docker container and stack management | sysadmin, fleet (pinned read-only instance) |
| [patchmon-mcp.md](patchmon-mcp.md) | patchmon-mcp | Apt patch management — retired 2026-10-26 | — |
| [pm2-mcp.md](pm2-mcp.md) | pm2-mcp | PM2 process management | sysadmin |
| [code-server-mcp.md](code-server-mcp.md) | code-server-mcp | code-server session management — retired 2026-10-28 | — |
| [plane-mcp.md](plane-mcp.md) | plane-mcp | Plane issue tracking — retired 2026-10-25 | — |
| [backrest-mcp.md](backrest-mcp.md) | backrest-mcp | Backup plan status, snapshots, restore (Backrest) | sysadmin |
| [datastore-mcp.md](datastore-mcp.md) | datastore-mcp | Read-only queries across 8 database backends — parked 2026-10-25 (not running) | — |
| [librechat-mcp.md](librechat-mcp.md) | librechat-mcp | LibreChat agent management (CRUD) | not yet wired |
| [vikunja-mcp.md](vikunja-mcp.md) | vikunja-mcp | Vikunja task/project management (token passthrough) | All agents |
| [doc-cache-mcp.md](doc-cache-mcp.md) | doc-cache-mcp | Docs cache list/add/sync with source-URL allowlist | research |

## Access Control

All servers are accessed through [scoped-mcp](../agent/scoped-mcp.md). Each agent's manifest defines which servers it can reach, with per-tool denylists, rate limits, and argument filters applied at the proxy level.
