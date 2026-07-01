# Tools Stack

A stack of eight stateless, browser-based web utilities on forge — PDF editing, diagramming, developer tooling, and image editing/conversion. Every service is a static single-page app served by nginx (or an equivalent static server); none has a database, a volume, or any write path. They exist purely as convenient LAN-accessible tools.

Because the apps store nothing and are only used from the local network, access is gated by a SWAG IP allow-list (`192.168.1.0/24`) rather than Authentik — no login screen. SWAG still terminates TLS with the wildcard `*.helmforge.me` cert, so each tool gets a clean HTTPS subdomain.

---

## Services

| Tool | URL | Container | Internal port | Purpose |
|------|-----|-----------|---------------|---------|
| BentoPDF | `pdf.helmforge.me` | `bentopdf` | 8080 | Client-side PDF editing / merge / split |
| draw.io | `draw.helmforge.me` | `drawio` | 8080 | Diagramming (drawio/diagrams.net) |
| Excalidraw | `excalidraw.helmforge.me` | `excalidraw` | 80 | Hand-drawn-style whiteboard / diagrams |
| IT-Tools | `it-tools.helmforge.me` | `it-tools` | 80 | Developer utility collection (encoders, converters, generators) |
| Omni-Tools | `omni.helmforge.me` | `omni-tools` | 80 | General-purpose utility collection |
| CyberChef | `cyberchef.helmforge.me` | `cyberchef` | 8080 | GCHQ "cyber Swiss-army knife" — encode/decode/analyse |
| miniPaint | `paint.helmforge.me` | `minipaint` | 80 | In-browser raster image editor |
| VERT | `convert.helmforge.me` | `vert` | 80 | File format conversion |

All eight are proxied by SWAG and reachable only from the LAN. drawio also exposes 8443 (HTTPS) internally; the stack proxies the plain-HTTP port 8080. BentoPDF and CyberChef run as the nginx-unprivileged user (`101:101`) on port 8080; the rest use standard nginx on port 80.

---

## Architecture

| Container | Image | Notes |
|-----------|-------|-------|
| `bentopdf` | `ghcr.io/alam00000/bentopdf` (digest-pinned) | `user: 101:101`, `cap_drop: ALL` |
| `drawio` | `jgraph/drawio` (digest-pinned) | Tomcat; `user: 1001:999`, `cap_drop: ALL` |
| `excalidraw` | `excalidraw/excalidraw` (digest-pinned) | nginx root-start (`no-new-privileges` only) |
| `it-tools` | `ghcr.io/corentinth/it-tools` (digest-pinned) | nginx root-start |
| `omni-tools` | `ghcr.io/iib0011/omni-tools` (digest-pinned) | nginx root-start |
| `cyberchef` | `ghcr.io/gchq/cyberchef` (digest-pinned) | `user: 101:101`, `cap_drop: ALL` |
| `minipaint` | `minipaint:local` (built from source) | nginx:alpine root-start |
| `vert` | `ghcr.io/vert-sh/vert` (digest-pinned) | nginx root-start |

All images are pinned by SHA256 digest. Every container runs `restart: unless-stopped`, `no-new-privileges:true`, and tight `mem_limit`/`cpus` caps (128–512 MB). Containers that can drop all Linux capabilities do; the four nginx root-start images require `CHOWN` + `NET_BIND_SERVICE` at init, so they keep the default cap set with `no-new-privileges` as the mitigation (the established forge pattern — same as homepage).

### miniPaint from source

miniPaint has no suitable published image, so it is built locally from a two-stage Dockerfile (`~/docker/tools/minipaint/`): a `node:22-alpine` build stage clones the upstream repo at tag `v4.14.3`, runs `npm ci && npm run build`, then copies `dist/` into an `nginx:alpine` runtime stage. Both base images are digest-pinned. Bump the version by changing the `--branch` tag in the Dockerfile and rebuilding.

---

## Networks

| Network | Purpose |
|---------|---------|
| `forge-net` (external) | SWAG ingress for all eight containers |

Every service joins only `forge-net`. There are no host port bindings — SWAG is the sole ingress. These are pure static file servers with no upstream calls and no write paths, so east-west isolation between them is not warranted (audit-accepted, matching the kiwix-offline pattern).

---

## Configuration

- Stack directory: `~/docker/tools/`
  - `docker-compose.yml` — all eight services
  - `minipaint/Dockerfile` — local miniPaint build
- Appdata: none — the stack is stateless (no volumes, no `.env`)

### SWAG proxy-confs

Each tool has a `<sub>.subdomain.conf` in `/opt/appdata/swag/nginx/proxy-confs/`. The confs use the LAN allow-list gate instead of the Authentik includes:

```nginx
allow 192.168.1.0/24;
deny all;
```

No `authentik-server.conf` / `authentik-location.conf` includes. SWAG sees direct client IPs (no Cloudflare / `real_ip`), so the allow-list is what actually keeps these off the public internet even though `*.helmforge.me` resolves publicly and SWAG listens on `0.0.0.0:443`. To grant access from the storage/management subnet, add `allow 10.10.1.0/24;`.

---

## Security notes

From the 2026-06-30 audit (`tools-stack-2026-06`, result PASS — one Low fixed):

- **miniPaint Dockerfile pinning** (Low, fixed): the build now clones a fixed upstream tag (`v4.14.3`) and pins both base images by digest, rather than tracking a moving branch.
- **No auth by design** (accepted): LAN IP allow-list only. Appropriate because the tools are stateless and LAN-scoped; if any later needs off-LAN access, add Authentik forward auth to that tool's proxy-conf.
- **All on `forge-net`** (F-2, accepted): no per-tool network isolation — pure static servers with no upstream calls or write paths.
- **BentoPDF WASM from CDN** (F-4, accepted): BentoPDF loads WASM modules from jsDelivr at runtime. Client-side only, no file upload, LAN-only use — low CDN-compromise risk for internal tooling.
- **nginx root-start caps** (F-3, accepted): excalidraw, it-tools, omni-tools, miniPaint, and vert need `CHOWN` + `NET_BIND_SERVICE` at init; `cap_drop: ALL` breaks them, so `no-new-privileges` is applied instead.

---

## Operations

### Restart

```bash
cd ~/docker/tools && docker compose down && docker compose up -d
```

### Rebuild miniPaint

```bash
cd ~/docker/tools && docker compose build minipaint && docker compose up -d minipaint
```

### Health check

```bash
# Containers
docker ps --filter network=forge-net --format 'table {{.Names}}\t{{.Status}}' | grep -E 'bentopdf|drawio|excalidraw|it-tools|omni-tools|cyberchef|minipaint|vert'

# Through SWAG from the internal network (expect 200/302)
docker exec swag curl -sI http://cyberchef:8080
docker exec swag curl -sI http://excalidraw:80
```

### Logs

```bash
cd ~/docker/tools && docker compose logs --tail=50 <service>
```

### Verify the LAN gate

A request with a non-LAN source IP should return `403` (the `deny all` path). From on-LAN the tools return `200`/`302`.

---

## Dependencies

| Depends on | Why |
|------------|-----|
| `forge-net` | SWAG proxy access |
| SWAG | TLS termination, subdomain routing, LAN allow-list gate |

Nothing depends on the tools stack — the utilities are leaf services.

---

## Related docs

- [SWAG component doc](../foundation/swag.md)
- [kiwix component doc](../ai-search/kiwix.md) — same "LAN-only static service, single network, audit-accepted" pattern
