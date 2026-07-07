# librechat-mcp

FastMCP server for LibreChat agent management. Wraps the LibreChat REST API to give forge
agents programmatic CRUD access to LibreChat agents (create, read, update, delete, list),
handling JWT authentication transparently. Runs as a sidecar inside the LibreChat stack.

## Service

| Field | Value |
|-------|-------|
| Container | `librechat-mcp` |
| Image | `ghcr.io/tadmstr/librechat-mcp:latest` |
| Stack | `~/docker/librechat/` (sidecar in the LibreChat compose) |
| Port | `127.0.0.1:8496` (streamable-http) |
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

Authentication uses LibreChat's `POST /api/auth/login` endpoint. The JWT is cached
in-process and refreshed proactively after 6 days (LibreChat's default token lifetime is
7 days); a 401 triggers an immediate re-login.

## Tools

| Tool | Description |
|------|-------------|
| `list_agents` | List agents, optionally filtered by `search` (max `limit` 100) |
| `get_agent` | Fetch a single agent by `agent_id` |
| `create_agent` | Create an agent (`provider`, `model` required) |
| `update_agent` | Partial update — only the fields supplied change |
| `delete_agent` | Delete an agent by `agent_id` |
| `list_tools` | List tool capabilities available for agent creation |

`agent_id` must match `^[a-zA-Z0-9_-]+$`; IDs come from `list_agents` / `create_agent`.

## Dependencies

- **LibreChat** container (`librechat:3080`) — must be up for JWT login and API calls;
  `depends_on: librechat`
- LibreChat admin account credentials in `~/docker/librechat/.env`

## scoped-mcp Access

Not yet registered in the agent scoped-mcp manifests. When wired, register as
streamable-http at `http://127.0.0.1:8496/mcp`.

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
- LibreChat stack: `~/docker/librechat/` (vhost `librechat.helmforge.me`)
