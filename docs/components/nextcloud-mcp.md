# nextcloud-mcp

nextcloud-mcp is a FastMCP server that exposes Nextcloud operations as MCP tools — `occ`
admin commands executed via `docker exec`, OCS Provisioning API calls for user/group
management, and WebDAV file operations. It gives forge agents structured access to the
Nextcloud instance without requiring shell access.

- **Package:** `nextcloud-mcp` v0.1.0 (TadMSTR/nextcloud-mcp)
- **Repo:** `/home/ted/repos/personal/nextcloud-mcp/`
- **Venv:** `/opt/venvs/nextcloud-mcp/`
- **Transport:** streamable-http — `127.0.0.1:8500` (PM2, `ecosystem.config.js`)
- **Nextcloud URL:** `https://nextcloud.helmforge.me`
- **Env file:** `/opt/appdata/nextcloud-mcp/env` (0600, admin credentials)
- **Manifest:** `~/.claude/manifests/nextcloud-mcp.yaml`
- **Log:** stdout via PM2 (JSON structlog)

## Port / endpoint

| Binding | Purpose |
|---------|---------|
| `127.0.0.1:8500` | FastMCP streamable-http — all MCP tool calls |

Port 8500 is localhost-only; scoped-mcp proxies agent connections.

## Configuration

Env file at `/opt/appdata/nextcloud-mcp/env` (chmod 600):

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `NEXTCLOUD_URL` | Yes | — | `https://nextcloud.helmforge.me` on forge |
| `NEXTCLOUD_CONTAINER` | No | `nextcloud` | Docker container name for occ exec |
| `NEXTCLOUD_ADMIN_USER` | No | `admin` | Admin username for OCS/share tools |
| `NEXTCLOUD_ADMIN_PASSWORD` | Yes* | — | Admin app password (*or use Vault) |
| `NEXTCLOUD_VAULT_ADDR` | No | — | Vault address for credential brokering |
| `NEXTCLOUD_VAULT_TOKEN` | No | — | Vault token (required with VAULT_ADDR) |
| `NEXTCLOUD_VAULT_ADMIN_PATH` | No | `secret/data/nextcloud/admin` | Vault KV v2 path |
| `FASTMCP_TRANSPORT` | Yes | `stdio` | Set to `streamable-http` |
| `FASTMCP_PORT` | Yes | `8000` | Set to `8500` |
| `FASTMCP_HOST` | No | `127.0.0.1` | Bind host |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | — | SigNoz gRPC at `http://localhost:4317` |
| `LOG_LEVEL` | No | `INFO` | Log verbosity |

## Tool groups

| Group | Scope | Count | Description |
|-------|-------|-------|-------------|
| `occ-admin` | sysadmin | 17 | Version, maintenance, apps, config, files, DB, FTS, security |
| `ocs-provisioning` | sysadmin | 6 | User/group management, app password generation |
| `files` | per-agent | 8 | WebDAV list/get/put/move/delete, share create/list/delete |

`occ-admin` and `ocs-provisioning` tools authenticate as admin and are sysadmin-only.
`files` tools accept per-call `username`/`password` for agent-specific file access.
Share tools use admin credentials (cross-user share management requires admin auth).

## Dependencies

| Dependency | Notes |
|------------|-------|
| Docker socket | `occ` tools run via `docker exec nextcloud occ ...` |
| Nextcloud container | Must be named `nextcloud` (or override `NEXTCLOUD_CONTAINER`) |
| Nextcloud HTTP | OCS and WebDAV tools call `https://nextcloud.helmforge.me` directly |
| Vault (optional) | Admin credentials can be fetched from `secret/data/nextcloud/admin` |

`occ` commands are executed with `--no-ansi`. `--value` arguments are redacted in logs.

## Operations

**Health check:**
```bash
curl -s http://127.0.0.1:8500/health
```

**Restart:**
```bash
pm2 restart nextcloud-mcp
pm2 logs nextcloud-mcp --lines 50
```

**Reload env file changes:**
```bash
pm2 stop nextcloud-mcp
export $(grep -v '^#' /opt/appdata/nextcloud-mcp/env | xargs)
pm2 start nextcloud-mcp
```

**Check process status:**
```bash
pm2 show nextcloud-mcp
```

## scoped-mcp integration

Manifest: `~/.claude/manifests/nextcloud-mcp.yaml`

| Agent | Access |
|-------|--------|
| sysadmin | All 31 tools (`tools: "*"`) |
| developer | `files` group (8 tools) |
| research | `dav_list`, `dav_get`, `share_list` |
| writer | `dav_list`, `dav_get`, `dav_put`, `share_create`, `share_list` |
| security | `dav_list`, `occ_status`, `security_check`, `log_tail` |

No internal authentication layer — access control is enforced entirely by scoped-mcp grants.

## Security notes

- Admin credentials are not logged; `--value` args in occ commands are redacted as `[REDACTED]`
- WebDAV path validation rejects `..` traversal sequences (both raw and percent-encoded)
- `username`, `group_id`, and `share_id` are validated against allowlist regexes before use
- `app_password_create` generates the password via `secrets.token_urlsafe` and injects it
  via `docker exec -e OC_PASS` — never logged by this server
- Vault KV v2 path format: path must include `/data/` (e.g. `secret/data/nextcloud/admin`)
- Security audit: `nextcloud-mcp-2026-06` (2026-06-21, 5 findings resolved: F-01 through F-05)
