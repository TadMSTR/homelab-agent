# Ketesa

Web-based Synapse administration UI, deployed as a companion to the Matrix homeserver. Provides a browser interface for room management, user management, and homeserver inspection without requiring direct admin API scripting.

## Why It Exists

Synapse's admin API (`/_synapse/admin/`) is fully functional but requires crafting HTTP requests manually or using CLI tools. Ketesa wraps these endpoints in a GUI — user search, room listing, device management, federation controls — making routine admin tasks accessible without a terminal session.

The alternative was scripting every admin action through matrix-mcp or curl. For infrequent one-off operations (suspending a user, purging a room, reviewing federation state) the GUI overhead is worth it.

## Architecture

Ketesa is a purely client-side application: the browser fetches static assets from the Ketesa container, then makes admin API calls directly from the browser to Synapse. There is no Ketesa backend proxy step.

```
Browser (operator, LAN)
  │
  ├─── SWAG (ketesa.yourdomain) ──────► Ketesa container (port 80, claudebox-net)
  │    Authelia SSO gate                 Static UI assets only
  │
  └─── SWAG (matrix.yourdomain) ──────► Synapse /_synapse/admin/
       LAN-allowlist gate                Admin API (token required by Synapse natively)
```

The browser loads the UI from `ketesa.yourdomain`, then issues admin API requests to `matrix.yourdomain/_synapse/admin/`. Both SWAG vhosts are required. The `/_synapse/admin/` path is restricted to LAN CIDRs at the proxy layer (`192.168.0.0/16`, `10.10.0.0/16`) — external requests return 403 regardless of credentials. Synapse also enforces admin token authentication natively on all admin endpoints.

## Stack

| Container | Image | Purpose |
|-----------|-------|---------|
| `ketesa` | `ghcr.io/etkecc/ketesa@sha256:6906708d747...` | Synapse admin UI (static assets) |

Runs on `claudebox-net`. No host port — internal only. SWAG routes `ketesa.yourdomain` to port 80 inside the network.

**Tracked in:** `docker/matrix/docker-compose.yml` (claudebox-docker repo)

**Not git-tracked:**
- `/opt/appdata/matrix/ketesa/config.json` — sets `restrictBaseUrl` to `matrix.yourdomain`; prevents the UI from being pointed at arbitrary Synapse instances
- `/opt/appdata/matrix/swag/nginx/proxy-confs/ketesa.subdomain.conf` — SWAG vhost with Authelia forward auth

## Access

- **URL:** `ketesa.yourdomain`
- **Auth:** Authelia SSO required to reach the UI; Synapse admin credentials required in-browser for API calls
- **Network:** LAN only (SWAG does not forward Ketesa or the admin API path externally)

## Synapse Hardening Applied Alongside

These `homeserver.yaml` settings were applied during the Ketesa deployment build. They are not git-tracked (homeserver.yaml lives in appdata, modified via `docker exec`):

| Setting | Value | Effect |
|---------|-------|--------|
| `allow_guest_access` | `false` | Prevents unauthenticated guest account creation |
| `allow_public_rooms_over_federation` | `false` | Hides room directory from federated servers |
| `allow_public_rooms_without_auth` | `false` | Requires auth to browse the local room directory |
| `auto_join_rooms` | `['#announcements:yourdomain']` | New accounts auto-join the announcements room |

## Security

- **SWAG admin path:** `/_synapse/admin/` restricted to LAN CIDRs (`192.168.0.0/16`, `10.10.0.0/16`) at the proxy — external access returns 403
- **Synapse native enforcement:** Admin token required on all `/_synapse/admin/` endpoints regardless of proxy rules
- **Ketesa container hardening:** `read_only: true`, `tmpfs` for writable paths, `mem_limit`, `cpus` constraints, `cap_drop: ALL`, `no-new-privileges: true`
- **restrictBaseUrl:** `config.json` locks the UI to a single Synapse instance — the UI cannot be redirected to an arbitrary homeserver
- **Image pinned by digest:** Auto-update blocked (no version tag available from registry labels); updates require manual digest bump

## Related Docs

- [matrix.md](matrix.md) — Synapse homeserver, matrix-mcp, and the full Matrix stack
- [swag.md](swag.md) — SWAG reverse proxy configuration
- [authelia.md](authelia.md) — Authelia SSO integration
