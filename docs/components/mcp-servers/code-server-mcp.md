# code-server-mcp

FastMCP server wrapping the code-server Docker container. Provides MCP tools for
health checks, deep-link URL generation, extension listing, and extension installation.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `code-server-mcp` |
| Type | always-on |
| Interpreter | `~/repos/personal/code-server-mcp/venv/bin/python3` |
| Module | `code_server_mcp.server` |
| Port | `127.0.0.1:8498` (streamable-http) |
| Repo | `~/repos/personal/code-server-mcp/` (GitHub: TadMSTR/code-server-mcp) |

## Configuration

| Env Var | Value |
|---------|-------|
| FASTMCP_TRANSPORT | streamable-http |
| FASTMCP_PORT | 8498 |
| FASTMCP_HOST | 127.0.0.1 |
| CODESERVER_URL | http://127.0.0.1:8443 |
| CODESERVER_PUBLIC_URL | https://code.helmforge.me |
| CODESERVER_CONTAINER | code-server |
| CODESERVER_BIN | /app/code-server/bin/code-server |

## Tools

| Tool | Description |
|------|-------------|
| health_check | Check code-server container health |
| open_folder_url | Generate deep-link URL for a repo path (allowlist: /home/ted/repos, /home/ted/docker) |
| list_extensions | List installed VS Code extensions |
| install_extension | Install extension by marketplace ID (regex-validated) |

## Dependencies

- **code-server** Docker container (port 8443)
- **scoped-mcp** — all agents access via scoped-mcp manifests

## scoped-mcp Access

| Agent | Access |
|-------|--------|
| sysadmin | full access (all 4 tools) |
| developer | full access |
| research | install_extension denied |

## Operations

```bash
# Check status
pm2 show code-server-mcp

# View logs
pm2 logs code-server-mcp --lines 30

# Restart
pm2 restart code-server-mcp
```

## Related Docs

- [code-server.md](../cicd/code-server.md) — Docker container it wraps
