# Grafana MCP

Grafana MCP is an SSE-based Model Context Protocol server that exposes Grafana's API
to AI agents. On forge it is registered in the sysadmin agent's scoped-mcp config,
giving the sysadmin agent read access to dashboards, panels, and alert state.

- **Image:** `grafana/mcp-grafana:latest` (SHA-pinned in compose)
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Network:** `forge-monitoring`
- **Port:** `127.0.0.1:8014` → container port 8000

## Critical: Docker Image Only

`@grafana/mcp-grafana` does **not** exist as an npm package. The only distribution is
the Docker image `grafana/mcp-grafana:latest`. Attempting to run via `npx
@grafana/mcp-grafana` or `npm install -g @grafana/mcp-grafana` will fail with a package
not found error.

## Container Configuration

```yaml
command:
  - -address=0.0.0.0:8000
ports:
  - "127.0.0.1:8014:8000"   # localhost-only; not on LAN
env_file:
  - /home/ted/.secrets/forge.env
environment:
  - GRAFANA_URL=http://grafana:3000
```

`GRAFANA_URL` points to the Grafana container on `forge-monitoring`. The `GRAFANA_API_KEY`
variable is sourced from `forge.env`.

## API Key Scope

The `GRAFANA_API_KEY` is a **service account token with Editor role** and
`isGrafanaAdmin=false`. This gives the MCP server read/write access to dashboards and
panels, but no admin-level permissions (no user management, no org settings, no LDAP).

Confirmed clean at audit 2026-05-24:
- Grafana API `/api/access-control/user/permissions` returned no admin-level permissions

## Sysadmin Agent Registration

Registered in `/opt/agents/sysadmin/config/scoped-mcp.json`:

```json
{
  "type": "mcp_proxy",
  "name": "grafana-mcp",
  "url": "http://localhost:8014"
}
```

The sysadmin agent accesses Grafana dashboards and alert state through this MCP proxy.
All calls are logged to the scoped-mcp audit log at
`/opt/appdata/agents/sysadmin/audit/scoped-mcp.log`.

## Security

- Bound to `127.0.0.1:8014` — not accessible from LAN or other containers
- Editor-scoped API key, no admin permissions
- Token in `forge.env` (chmod 600)
- Service on `forge-monitoring` only; not on `forge-net`

## Related Docs

- [forge-observability-stack.md](../../phases/forge-observability-stack.md) — build narrative
