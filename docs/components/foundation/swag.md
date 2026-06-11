# SWAG

SWAG (Secure Web Application Gateway) is forge's reverse proxy and SSL termination layer.
It handles all inbound HTTPS traffic to `helmforge.me` subdomains, issues and renews
wildcard certificates via Cloudflare DNS validation, and routes requests to backend
services on the `forge-net` Docker network.

- **Image:** `lscr.io/linuxserver/swag:latest`
- **Ports:** 80, 443 (public)
- **Appdata:** `/opt/appdata/swag/`
- **Network:** `forge-net`

## SSL

Wildcard cert for `*.helmforge.me` via Let's Encrypt + Cloudflare DNS-01 validation.
`STAGING=false` — production certs. Renewal is automatic. Certs at
`/opt/appdata/swag/etc/letsencrypt/`.

## Active Proxy Confs

| Conf | Service | Subdomain |
|------|---------|-----------|
| `authentik.subdomain.conf` | Authentik SSO | `auth.helmforge.me` |
| `cloudcli.subdomain.conf` | CloudCLI web UI | `cloudcli.helmforge.me` |
| `dockhand.subdomain.conf` | Dockhand stack manager | `dockhand.helmforge.me` |
| `docs.subdomain.conf` | Owners manual static site | `docs.helmforge.me` |
| `grafana.subdomain.conf` | Grafana dashboards | `grafana.helmforge.me` |
| `hister.subdomain.conf` | Hister memory search | `hister.helmforge.me` |
| `hvault.subdomain.conf` | HashiCorp Vault | `hvault.helmforge.me` |
| `influxdb.subdomain.conf` | InfluxDB 3 | `influxdb.helmforge.me` |
| `ketesa.subdomain.conf` | Synapse admin UI | `ketesa.helmforge.me` |
| `langfuse.subdomain.conf` | Langfuse observability | `langfuse.helmforge.me` |
| `matrix.subdomain.conf` | Synapse Matrix API | `matrix.helmforge.me` |
| `ollama.subdomain.conf` | Ollama LLM API | `ollama.helmforge.me` |
| `open-webui.subdomain.conf` | Open WebUI | `ai.helmforge.me` |
| `patchmon.subdomain.conf` | Patchmon patch manager | `patchmon.helmforge.me` |
| `searxng.subdomain.conf` | SearXNG search | `search.helmforge.me` |
| `signoz.subdomain.conf` | SigNoz APM | `signoz.helmforge.me` |
| `vaultwarden.subdomain.conf` | Vaultwarden passwords | `vault.helmforge.me` |

## Per-Service Auth Model

| Service | Auth in Proxy Conf | Why |
|---------|-------------------|-----|
| Authentik | None | IdP — manages its own sessions |
| Grafana | None | Native OIDC — Grafana handles auth directly |
| InfluxDB | Forward auth | No native SSO |
| SearXNG | Forward auth | No native SSO |
| Ketesa | Forward auth | Admin UI — Authentik-gated |
| Vaultwarden | None | Bitwarden clients don't follow forward auth redirects |
| All others | Forward auth | Default policy for new services |

## Forward Auth Pattern (LSIO Authentik Integration)

LSIO's SWAG image ships two Authentik include files:
- `authentik-server.conf` — registers Authentik as the auth upstream
- `authentik-location.conf` — adds the `auth_request` block to each location

A service conf using forward auth:

```nginx
server {
    listen 443 ssl;
    server_name searxng.helmforge.me;

    include /config/nginx/ssl.conf;
    include /config/nginx/authentik-server.conf;

    location / {
        include /config/nginx/authentik-location.conf;
        include /config/nginx/proxy.conf;
        proxy_pass http://searxng:8080;
    }
}
```

## OIDC Services (No Forward Auth in Proxy Conf)

Grafana uses OIDC directly. The proxy conf is a plain pass-through — Authentik handles
the OIDC callback at `grafana.helmforge.me/login/generic_oauth`. SWAG just proxies.

## Domain-Level Cookie Scope

The Authentik forward auth proxy provider is configured with a domain-level cookie
(`helmforge.me` as the cookie domain, not per-subdomain). A single Authentik login
covers all forward-auth-protected subdomains. Requires:
1. The Authentik proxy provider's "cookie domain" set to `helmforge.me`
2. All SWAG proxy confs using the same `authentik-server.conf` / `authentik-location.conf` includes

## Static Content

The Owner's Manual static site (`~/repos/personal/helm-owners-manual/site/`) is mounted read-only at
`/config/www/owners-manual` and served at `docs.helmforge.me`.

## Network Placement

SWAG is on `forge-net` only. Backend services that need SWAG routing must also be on
`forge-net`. Services that communicate only internally (database sidecars, etc.) stay on
isolated internal networks and do not need `forge-net` membership.

## Related Docs

- [authentik.md](authentik.md) — provider setup, OIDC config, bootstrap recovery
