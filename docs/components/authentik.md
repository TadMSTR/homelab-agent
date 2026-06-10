# Authentik

Authentik is forge's identity provider and SSO gateway. It handles SSO for all web
services via both domain-level forward auth (a single login gate covering all protected
subdomains) and per-service OIDC for apps that support it natively. All admin-facing
UIs on `helmforge.me` route through Authentik before reaching their backend.

- **Image:** `ghcr.io/goauthentik/server:2026.2.1`
- **URL:** `auth.helmforge.me`
- **Appdata:** `/opt/appdata/authentik/`

## What Authentik Provides

**Domain-level forward auth** — A single Authentik session covers all services that use
the forward auth proxy provider. Log in once at `auth.helmforge.me`, and the session
cookie is valid for every service under `*.helmforge.me`. Services without their own
auth can rely entirely on this gate.

**Per-service OIDC** — Apps with native SSO support use OAuth2/OIDC directly. Authentik
acts as the identity provider; the app handles its own session and role mapping. Grafana
uses this to map Authentik group membership to admin/viewer roles.

## Stack

| Container | Role |
|-----------|------|
| `authentik-server` | API + web UI (ports 9000/9443) |
| `authentik-worker` | Background tasks, blueprint execution |
| `authentik-postgres` | Database backend (`postgres:16-alpine`) |

`authentik-postgres` is on the `authentik-internal` bridge network only. The server and
worker bridge both networks: `authentik-internal` for the database, `forge-net` for SWAG
proxy access.

The worker container mounts `docker.sock` for Docker outpost management. The
**Embedded Outpost** (built into the server container) handles all forward auth and
OIDC flows — no separate outpost deployment needed for a single-host setup. SWAG proxies
auth challenges to the Authentik server using LSIO-provided `authentik-server.conf` and
`authentik-location.conf` include files.

## Provider Types in Use

### Forward Auth (Domain-Level)

Configured as a Proxy Provider with domain-level cookie scope (`helmforge.me` cookie
domain). One provider covers all subdomains. Services opt in by including the Authentik
middleware in their SWAG proxy conf — no per-service Authentik configuration needed.

### OIDC / OAuth2

Configured as an OAuth2/OIDC provider per application. Used when the target app has
native SSO support and benefits from role mapping or deeper integration.

Grafana uses OIDC with JMESPath role mapping:
```
contains(groups, 'authentik Admins') && 'Admin' || 'Viewer'
```

### No Auth (Intentional)

Vaultwarden intentionally bypasses Authentik — Bitwarden clients don't support forward
auth redirects. The SWAG proxy conf passes traffic through without auth middleware.

## Per-Service Auth Model

| Service | Auth Type | Notes |
|---------|-----------|-------|
| SearXNG | Forward auth | Domain-level cookie |
| InfluxDB | Forward auth | Domain-level cookie |
| Grafana | OIDC | Native SSO, admin/viewer role mapping |
| Ketesa | Forward auth | Synapse admin UI |
| Vaultwarden | None | Bitwarden client compat |
| Authentik itself | Self | Admin UI protected by its own session |

## Adding a New Protected Service

1. Create an Application in the Authentik admin UI (`auth.helmforge.me/if/admin/`)
2. Create a Proxy Provider (for forward auth) or OAuth2 Provider (for OIDC)
3. Add the Authentik middleware to the service's SWAG proxy conf

For forward auth, add two lines to the SWAG server block:
```nginx
include /config/nginx/authentik-server.conf;

location / {
    include /config/nginx/authentik-location.conf;
    include /config/nginx/proxy.conf;
    proxy_pass http://backend:port;
}
```

## Blueprints

Custom blueprints live at `/opt/appdata/authentik/blueprints/`. Keep custom blueprints
out of `/blueprints/default/` and `/blueprints/system/` — volume mounts that shadow
those paths cause blueprints to fail silently.

## Bootstrap and Recovery

**Initial admin token** — check server logs on first start:
```bash
docker logs authentik-server | grep "Initial admin"
```

**Password recovery** — if the admin account is locked out:
```bash
docker exec -it authentik-worker ak create_recovery_key 10 akadmin
```
Generates a recovery link valid for 10 uses.

## Accepted Risks

**Grafana break-glass:** Grafana's local login form is disabled
(`GF_AUTH_DISABLE_LOGIN_FORM=true`). If Authentik becomes unavailable, Grafana is
inaccessible. Mitigation: re-enable via a compose override and restart Grafana.

## Related Docs

- [swag.md](swag.md) — proxy conf pattern and forward auth integration detail
