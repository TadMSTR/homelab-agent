# SWAG

SWAG (Secure Web Application Gateway) is the reverse proxy that fronts every web-accessible service in the stack. It handles wildcard SSL certificates via Let's Encrypt with Cloudflare DNS validation, routes `*.yourdomain` subdomains to the correct container, and integrates with Authelia for SSO. It also ships a built-in dashboard for monitoring proxy status.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture as the single ingress point for all services.

## Why SWAG

I needed a reverse proxy that made it easy to add new services without touching nginx config from scratch every time. SWAG ships with 300+ pre-built proxy conf templates — for most services, you rename a `.sample` file and you're done. The first-class Authelia integration is two `include` lines per proxy conf. And the LinuxServer.io container handles Let's Encrypt renewal automatically.

The alternatives were Traefik and Caddy. Traefik's label-based config is elegant but harder to debug when something goes wrong — I'd rather see an nginx conf file I can read. Caddy is excellent but has less community support for the specific services I run. SWAG hit the sweet spot of convenience, transparency, and ecosystem support.

## How It Works

SWAG runs as a single container that combines nginx, certbot, and fail2ban. On startup, it requests a wildcard SSL certificate from Let's Encrypt using Cloudflare DNS-01 validation. This means the domain doesn't need to resolve publicly — it can point to an internal IP via split-horizon DNS or a local DNS server. No ports forwarded to the internet.

All services share a single Docker network. SWAG routes traffic based on subdomain: `chat.yourdomain` goes to LibreChat, `auth.yourdomain` goes to Authelia, `perplexica.yourdomain` goes to Perplexica, and so on. Each service gets its own proxy conf file in `/config/nginx/proxy-confs/`.

| Subdomain | Service | Port |
|-----------|---------|------|
| `auth.*` | Authelia | 9091 |
| `backrest.*` | Backrest (systemd, cross-host) | 9898 |
| `chat.*` | LibreChat | 3080 |
| `cui.*` | Claude Code Web UI | 3001 |
| `dashboard.*` | SWAG Dashboard | 81 (internal) |
| `dockhand.*` | Dockhand | 3000 |
| `notebook.*` | Open Notebook | 8502 / 5055 |
| `perplexica.*` | Perplexica | 3000 |

## Prerequisites

- A domain name with DNS managed by Cloudflare (other providers are supported but Cloudflare is the most common for DNS validation)
- A Cloudflare API token with `Zone:DNS:Edit` permissions — SWAG needs this for DNS-01 challenges
- Docker CE + Compose
- A shared Docker network that all your services will join

## Configuration

The compose file is at [`docker/swag/docker-compose.yml`](../../docker/swag/docker-compose.yml). The key configuration happens through environment variables and volume-mounted config files.

### Cloudflare DNS Credentials

SWAG expects a credentials file at `/config/dns-conf/cloudflare.ini`:

```ini
# Cloudflare API token (not the Global API Key)
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
```

Use a scoped API token, not the Global API Key. Create one in the Cloudflare dashboard under My Profile → API Tokens → Create Token → Edit zone DNS template. Scope it to your specific zone.

### Proxy Conf Pattern

Each service behind SWAG gets a proxy conf file. SWAG ships with hundreds of `.sample` files — for supported services, just rename to remove `.sample`. For custom services, the pattern is straightforward:

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name myservice.*;

    include /config/nginx/ssl.conf;

    # Authelia SSO — uncomment both lines to protect this service
    include /config/nginx/authelia-server.conf;

    location / {
        # Authelia SSO — must pair with the server-level include above
        include /config/nginx/authelia-location.conf;

        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app myservice;       # Container name
        set $upstream_port 8080;           # Container's listening port
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;

        # Add WebSocket support if the service needs it:
        # proxy_set_header Upgrade $http_upgrade;
        # proxy_set_header Connection $http_connection;
    }
}
```

The Authelia integration is the key part — two `include` lines (one at server level, one at location level) and every request to that subdomain goes through SSO. No per-service authentication config needed.

With `SWAG_AUTORELOAD=true`, nginx reloads automatically when you add or modify proxy conf files. No manual `docker exec swag nginx -s reload` needed.

### SWAG Dashboard

The `linuxserver/mods:swag-dashboard` Docker mod adds a built-in status dashboard accessible at `dashboard.yourdomain`. It shows active proxy confs, certificate status, and fail2ban stats. The dashboard listens on port 81 internally and is proxied through the standard SWAG nginx config. In my setup, it's restricted to RFC 1918 ranges (no Authelia) since it's informational only.

## Integration Points

SWAG is the connective tissue between the browser and every other service in the stack. Every component doc in this repo that mentions a `*.yourdomain` URL is routing through SWAG.

The most important integration is with [Authelia](authelia.md). SWAG's nginx config includes pre-built Authelia snippets (`authelia-server.conf` and `authelia-location.conf`) that handle the authentication handshake. Authelia itself runs as a container on the same Docker network — SWAG resolves it by container name.

SWAG also handles SSL for all inter-service communication from the browser's perspective. Internal container-to-container traffic stays on HTTP over the Docker network, but everything from the browser to SWAG is TLS 1.2+.

## Gotchas and Lessons Learned

**Cloudflare API token scope matters.** Use a scoped token with `Zone:DNS:Edit` for your specific zone, not the Global API Key. The Global Key works but gives SWAG access to your entire Cloudflare account.

**DNS-01 validation can be slow.** Let's Encrypt DNS-01 challenges depend on DNS propagation. First cert issuance can take 2-5 minutes while Cloudflare propagates the TXT record. If it fails, check the SWAG logs — usually it's a token permissions issue, not a timing issue.

**Proxy conf naming convention.** SWAG auto-detects proxy confs based on filename pattern: `servicename.subdomain.conf` or `servicename.subfolder.conf`. The file must not end in `.sample` to be active. If your proxy conf isn't loading, check the filename.

**WebSocket support isn't automatic.** Services that use WebSockets (Dockhand, Perplexica, Open Notebook's Streamlit UI, LibreChat) need the `Upgrade` and `Connection` headers set in their proxy conf. Without these, the connection drops or falls back to polling.

**The `resolver.conf` include is important.** It tells nginx to use Docker's embedded DNS for container name resolution. Without it, nginx resolves container names at startup and caches the IP — if a container restarts and gets a new IP, nginx routes to a dead address until it's reloaded.

## Standalone Value

SWAG is useful for any Docker homelab, not just this stack. If you're running multiple services and want wildcard SSL with zero internet exposure, SWAG + Cloudflare DNS validation is one of the simplest paths. Add Authelia and you have SSO across everything with minimal per-service config.

## Further Reading

- [SWAG documentation](https://docs.linuxserver.io/general/swag/)
- [SWAG proxy conf samples](https://github.com/linuxserver/reverse-proxy-confs)
- [Cloudflare API token setup](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [SWAG + Authelia guide](https://www.authelia.com/integration/proxies/swag/)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where SWAG fits in the three-layer stack
- [Authelia](authelia.md) — SSO authentication that integrates with SWAG proxy confs
- [LibreChat](librechat.md) — primary service behind SWAG
- [Docker compose file](../../docker/swag/) — SWAG stack compose
