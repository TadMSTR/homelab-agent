# Grafana MCP

Grafana MCP is the upstream `mcp-grafana` Model Context Protocol server, which exposes
Grafana's API to AI agents. On forge it is a module in the sysadmin agent's scoped-mcp
manifest, giving the sysadmin agent access to dashboards, datasource queries, and alert
state.

- **Image:** `grafana/mcp-grafana:2.0.2` (digest-pinned in compose)
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Network:** `forge-monitoring`
- **Port:** `127.0.0.1:8014` → container port 8000
- **Transport:** streamable-http on `/mcp`
- **Runs as:** `65534:65534` (nobody), not the image's default user

## Critical: Docker Image Only

`@grafana/mcp-grafana` does **not** exist as an npm package. The distribution used here
is the Docker image `grafana/mcp-grafana`. Attempting to run via `npx
@grafana/mcp-grafana` or `npm install -g @grafana/mcp-grafana` will fail with a package
not found error.

## Version 2.x Upgrade Notes

The deployment moved from ~0.14 to 2.0.2. Changes that affected the config:

- **Host header allowlist.** Since v1.2 the server rejects any `Host` header outside
  `--allowed-hosts` with a 403. The default list covers only loopback variants of `:8000`,
  but agents reach the server through the `127.0.0.1:8014` port mapping and send
  `Host: localhost:8014`, so the published port must be listed explicitly. Never set
  `--allowed-hosts=*`: that disables the DNS-rebinding check.
- **Anonymous usage reporting** is on by default in v2.0.0. It is turned off with
  `GRAFANA_USAGE_STATS=disabled`.
- **`GRAFANA_API_KEY` is deprecated.** The token goes in `GRAFANA_SERVICE_ACCOUNT_TOKEN`.
- **Caller auth** is available via `MCP_GRAFANA_SERVER_TOKEN` (see below).

## Container Configuration

```yaml
image: grafana/mcp-grafana:2.0.2@sha256:<digest>
user: "65534:65534"
mem_limit: 256m
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
command:
  - --transport=streamable-http
  - --allowed-hosts=localhost:8014,127.0.0.1:8014,[::1]:8014
ports:
  - "127.0.0.1:8014:8000"   # localhost-only; not on LAN
environment:
  - GRAFANA_URL=http://grafana:3000
  - GRAFANA_USAGE_STATS=disabled
  - GRAFANA_SERVICE_ACCOUNT_TOKEN=${GRAFANA_MCP_SA_TOKEN}
  - MCP_GRAFANA_SERVER_TOKEN=${MCP_GRAFANA_SERVER_TOKEN}
  - GRAFANA_ORG_ID=1
```

The image `ENTRYPOINT` already passes `--transport sse --address 0.0.0.0:8000`. Compose
`command:` appends to it, and Go's flag package keeps the last `--transport`, so the server
ends up serving streamable-http on `/mcp`. Streamable-http is required because scoped-mcp's
`mcp_proxy` only sends custom headers (the caller-auth bearer) over that transport.

| Variable | Purpose |
|----------|---------|
| `GRAFANA_URL` | Grafana container on `forge-monitoring` |
| `GRAFANA_USAGE_STATS` | `disabled` — opts out of v2's default-on anonymous reporting |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | Grafana service account token the server uses to call Grafana |
| `MCP_GRAFANA_SERVER_TOKEN` | Bearer token callers must present (caller auth) |
| `GRAFANA_ORG_ID` | `1` — single-org Grafana. Without it every tool call logs "No org ID found" |

### Secrets

Secrets are passed **one variable at a time from the stack's `.env` file**
(`~/docker/observability/.env`), interpolated into the `environment:` list above. There is
no `env_file:` and no shared host-wide secrets file reaching this container; it receives
only the variables listed. To add a variable, add both the `.env` entry and an
`environment:` line, then recreate the container.

## Caller Authentication

Every request to the server must carry `Authorization: Bearer <token>`, where the token
matches `MCP_GRAFANA_SERVER_TOKEN`. Requests without it are rejected with **401**. The
token is supplied through the environment variable rather than the `--server-auth-token`
flag so it does not appear in the process arguments.

Callers hold their own copy of the same token. For the sysadmin agent, it lives in that
agent's own env file (sourced by its launcher) and is injected into the scoped-mcp module's
`headers:` block. The local port binding is therefore not the only gate: another local
process that can reach `127.0.0.1:8014` still needs the token.

## Service Account Scope

`GRAFANA_SERVICE_ACCOUNT_TOKEN` is a **Grafana service account token with Editor role** and
`isGrafanaAdmin=false`. This gives the MCP server read/write access to dashboards and
panels, but no admin-level permissions (no user management, no org settings, no LDAP, no
provisioning reload). Caller auth limits *who* can reach the server; it does not narrow
what the service account can do once reached.

All dashboards on forge are file-provisioned (see
[grafana-dashboards.md](grafana-dashboards.md)), so the dashboard-write tools fail on them by
design. Dashboard changes go through the provisioning files, not through this server.

## Tools

v2.0.2 groups tools into categories, enabled with `--enabled-tools` and switched off with
`--disable-<category>`. The default enabled set is:

`search`, `datasource`, `incident`, `prometheus`, `loki`, `alerting`, `dashboard`,
`folder`, `oncall`, `asserts`, `pyroscope`, `navigation`, `tempo`, `annotations`,
`rendering`, `snapshot`, `plugin`, `api`, `config`, `provisioning`, `docs`, `user`

Forge runs the default set. After the 2.0.2 upgrade the server listed 79 tools through
scoped-mcp. Per-tool names and parameters change
between releases; check `docker run --rm --entrypoint /app/mcp-grafana
grafana/mcp-grafana:<tag> --help` and the upstream README for the pinned tag rather than
relying on a list here.

Flags worth knowing for tightening the surface: `--disable-write` (drops create/update
tools), `--disable-api` (drops the raw datasource proxy), and `--loki-enforced-matchers`
(restricts readable Loki streams; requires `--disable-api` to be effective).

## Runtime User

The container runs as `user: "65534:65534"`. The image's own user (`mcp-grafana`) is
uid 1000, which on a typical single-user host is the primary login user. Without user
namespace remapping, a container escape would land as that uid, which owns the user's
secrets and is usually in the `docker` group. The binary is world-readable and executable
and keeps no state, so it runs unchanged as `nobody`.

## Sysadmin Agent Registration

Declared as a module in the sysadmin agent's scoped-mcp manifest
(`/etc/forge/manifests/sysadmin-agent.yml`):

```yaml
grafana-mcp:
  type: mcp_proxy
  config:
    url: http://localhost:8014/mcp
    headers:
      Authorization: "Bearer ${GRAFANA_MCP_SERVER_TOKEN}"
```

The `${GRAFANA_MCP_SERVER_TOKEN}` reference is resolved from the agent's environment at
broker start. A `headers:` block makes `mcp_proxy` use streamable-http, hence the `/mcp`
path rather than `/sse`. All calls are recorded in the sysadmin agent's scoped-mcp audit
logs under `/opt/appdata/agents/sysadmin/audit/`.

## Operations

```bash
# Container state and the user it runs as
docker ps --filter name=grafana-mcp
docker inspect grafana-mcp --format '{{.Config.User}}'

# Caller auth check: no token → 401
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8014/mcp

# Logs
docker logs --tail 50 grafana-mcp

# Recreate after a .env or compose change
cd ~/docker/observability && docker compose up -d grafana-mcp
```

## Security

- Bound to `127.0.0.1:8014` — not accessible from the LAN
- Host header allowlist limited to the published loopback addresses (no `*`)
- Caller auth: bearer token required on every request (401 without it)
- Runs as `65534:65534`, `cap_drop: ALL`, `no-new-privileges`, `mem_limit: 256m`
- Editor-scoped service account, no admin permissions
- Secrets passed per-variable from the stack `.env` (not a shared env file); token kept out
  of process args
- Anonymous usage reporting disabled
- Service on `forge-monitoring` only; not on `forge-net`

## Related Docs

- [grafana-dashboards.md](grafana-dashboards.md) — provisioned dashboards and alerting
- [loki-mcp.md](loki-mcp.md) — log queries for the same agents
