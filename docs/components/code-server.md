# code-server

VS Code in the browser, deployed as a Docker container on forge. Provides a web-based
code editor for repos and Docker configs without needing SSH or a local IDE.

## Service

| Field | Value |
|-------|-------|
| Container | `code-server` |
| Image | `lscr.io/linuxserver/code-server` (pinned digest) |
| Stack | `~/docker/code-server/` |
| Port | `127.0.0.1:8443` (proxied via SWAG) |
| Public URL | `https://code.helmforge.me` |
| Auth | Authentik forward auth |
| Appdata | `/opt/appdata/code-server` |
| Network | `forge-net` |

## Configuration

| Setting | Value |
|---------|-------|
| PUID / PGID | 1000 / 1000 |
| TZ | America/New_York |
| PROXY_DOMAIN | code.helmforge.me |
| DEFAULT_WORKSPACE | /repos |
| PASSWORD / SUDO_PASSWORD | empty (auth handled by Authentik) |

Volumes:
- `/opt/appdata/code-server:/config` — settings, extensions, user data
- `/home/ted/repos:/repos` (rw) — all repo directories accessible in the editor

## Security

- `cap_drop: ALL` with `cap_add: [SETUID, SETGID]` (minimum for s6-overlay UID transition)
- Memory limit: 2 GB, CPU limit: 2.0 cores
- Bound to `127.0.0.1` only — no direct external access
- Authentik forward auth on all paths

## Dependencies

- **SWAG** — reverse proxy and TLS termination
- **Authentik** — forward auth for access control
- **forge-net** Docker network

## Operations

```bash
# Check container status
docker ps -f name=code-server

# View logs
docker logs code-server --tail 50

# Restart
cd ~/docker/code-server && docker compose restart

# Rebuild (after compose changes)
cd ~/docker/code-server && docker compose up -d
```

## scoped-mcp Integration

code-server-mcp (port 8498) wraps this container, providing MCP tools for
health checks, deep-link URL generation, and extension management. See
[code-server-mcp.md](code-server-mcp.md).

## Related Docs

- [code-server-mcp.md](code-server-mcp.md) — MCP wrapper service
