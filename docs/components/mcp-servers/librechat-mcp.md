# librechat-mcp

FastMCP server for LibreChat agent management. Wraps the LibreChat REST API to give forge
agents programmatic management of LibreChat agents — CRUD, idempotent provisioning, version
history, sharing and role permissions, and discovery/validation lookups — handling JWT
authentication transparently. Runs as a sidecar inside the LibreChat stack.

## Service

| Field | Value |
|-------|-------|
| Container | `librechat-mcp` |
| Version | `0.3.0` (image `ghcr.io/tadmstr/librechat-mcp:0.3.0`, pinned — not `:latest`) |
| Stack | `~/docker/librechat/` (sidecar in the LibreChat compose) |
| Port | `127.0.0.1:8496` (streamable-http) — unchanged in 0.3.0 |
| Network | `librechat-internal` |
| Repo | `~/repos/personal/librechat-mcp/` (GitHub: TadMSTR/librechat-mcp) |

Deployed as a Docker sidecar rather than a PM2 process so it shares the LibreChat internal
network and can reach `http://librechat:3080` directly. The container is hardened:
`user: 1000:1000`, `cap_drop: ALL`, `no-new-privileges`, `mem_limit: 256m`.

## Configuration

| Env Var | Value |
|---------|-------|
| LIBRECHAT_URL | `http://librechat:3080` |
| LIBRECHAT_ADMIN_EMAIL | `${LIBRECHAT_MCP_EMAIL}` (from stack `.env`) |
| LIBRECHAT_ADMIN_PASSWORD | `${LIBRECHAT_MCP_PASSWORD}` (from stack `.env`) |
| MCP_PORT | `8496` |
| LIBRECHAT_MCP_API_TOKEN | `${LIBRECHAT_MCP_TOKEN}` (from stack `.env`, min 16 chars) — **mandatory as of 0.2.0**; the container refuses to start without it |

The MCP surface itself is bearer-token gated by `LIBRECHAT_MCP_API_TOKEN` — the loopback
port binding and the token are independent controls, not substitutes for each other.
Before 0.2.0 the endpoint had no auth at all.

Authentication to the LibreChat API uses `POST /api/auth/login`. The JWT is cached
in-process and refreshed proactively after 6 days (LibreChat's default token lifetime is
7 days); a 401 triggers an immediate re-login.

## Tools

22 tools in three groups (counted from the v0.3.0 source, the deployed version). Every tool
returns a **dict**. The [README](https://github.com/TadMSTR/librechat-mcp#tools) has the full
parameter detail.

### Agents (9)

| Tool | Description |
|------|-------------|
| `list_agents` | List agents, following the pagination cursor by default (`search`, `limit`, `expand`, `follow_cursor`) |
| `get_agent` | Fetch one agent by `agent_id` |
| `create_agent` | Create an agent (`provider`, `model` required, plus any of 28 writable fields and `mcp_servers`) |
| `update_agent` | Partial update — only the fields supplied change |
| `delete_agent` | Delete an agent by `agent_id` |
| `ensure_agent` | Idempotent create-or-update by `name` |
| `duplicate_agent` | Copy an agent, instructions and tools included |
| `list_agent_versions` | An agent's saved versions, oldest first |
| `revert_agent` | Restore a saved version (`version_index`) |

### Access control (7)

| Tool | Description |
|------|-------------|
| `get_agent_permissions` | Who can use an agent |
| `share_agent` | Grant or revoke access, or set public access |
| `search_principals` | Find users, groups or roles to grant to |
| `get_resource_access_roles` | Valid `accessRoleId` values for a resource type |
| `get_effective_permissions` | What the calling account can actually do |
| `get_role_permissions` | A role's full feature matrix |
| `set_role_permissions` | Change one permission type on a role |

### Discovery and validation (6)

| Tool | Description |
|------|-------------|
| `list_tools` | LibreChat's built-in tools |
| `list_mcp_tools` | MCP server tools, keyed by server |
| `list_mcp_servers` | Configured MCP servers with connection state |
| `list_models` | Model ids per provider (enabled providers only by default) |
| `list_categories` | Agent-picker categories with counts |
| `validate_agent_spec` | Check a spec against live lookups before writing it |

`agent_id` must match `^[a-zA-Z0-9_-]+$`; IDs come from `list_agents` / `create_agent`.

### Conventions and gotchas

- **Every tool returns a dict.** List-shaped results are wrapped as
  `{"<plural>": [...], "count": N}`. FastMCP refuses to serialise a bare list from a
  `-> dict` tool, so an unwrapped list fails on a *successful* upstream response — that is how
  `list_tools` was dead through MCP for all of v0.2.0 while its unit test passed. Four
  LibreChat endpoints return bare arrays and are wrapped; a test invokes every tool through
  the MCP layer to keep it that way.
- **Set `mcp_servers`, never `mcpServerNames`.** LibreChat derives `mcpServerNames`
  server-side from `tools` entries that carry the `_mcp_` delimiter, and its create/update
  schemas drop the field. Passing `mcpServerNames` returns 201 and changes nothing;
  `create_agent(mcp_servers=["searxng"])` expands to that server's tool keys.
- **The MCP endpoint needs the bearer token.** `LIBRECHAT_MCP_API_TOKEN` is mandatory from
  0.2.0 (see Configuration); clients send it as `Authorization: Bearer <token>`.

## Dependencies

- **LibreChat** container (`librechat:3080`) — must be up for JWT login and API calls;
  `depends_on: librechat`
- LibreChat admin account credentials in `~/docker/librechat/.env`

## scoped-mcp Access

Registered as streamable-http at `http://127.0.0.1:8496/mcp`, with the bearer token injected
as an `Authorization` header from the secrets store:

| Agent | Access |
|-------|--------|
| sysadmin | Full tool surface. `delete_agent`, `set_role_permissions` and `revert_agent` are HITL-gated (see [scoped-mcp.md](../agent/scoped-mcp.md#hitl-gates-sysadmin-developer-fleet)) |
| research | Read-only by `tool_allowlist`: `list_agents`, `get_agent`, `list_tools`. An allowlist rather than a denylist, so a tool added upstream is denied by default |

No other agent manifest registers librechat-mcp.

## Operations

```bash
# Status / logs
docker ps --filter name=librechat-mcp
docker logs librechat-mcp --tail 30

# Restart
cd ~/docker/librechat && docker compose restart librechat-mcp
```

Structured JSON logs via `structlog` (`librechat_auth_ok`,
`librechat_token_expired_refreshing`, per-tool events, `tool_error`).

## Related Docs

- [librechat-mcp README](https://github.com/TadMSTR/librechat-mcp) — usage examples
- LibreChat stack: `~/docker/librechat/` (vhost `librechat.example.com`)
