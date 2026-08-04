# Homepage

[gethomepage/homepage](https://gethomepage.dev) — a self-hosted dashboard giving Ted a
single landing page of service cards (status pings, container stats) for forge's stack.
Paired with a locked-down Docker socket proxy sidecar so the dashboard never touches
`docker.sock` directly.

- **URL:** `home.helmforge.me`
- **Stack directory:** `~/docker/homepage/`
- **Appdata:** `/opt/appdata/homepage/config`

---

## Architecture

| Container | Image | Role |
|-----------|-------|------|
| `homepage` | `ghcr.io/gethomepage/homepage` (digest-pinned) | Dashboard app — service cards, container stats |
| `homepage-socketproxy` | `tecnativa/docker-socket-proxy` (digest-pinned) | Read-only Docker API proxy — the only thing with socket access |

`homepage` depends on `homepage-socketproxy` and reaches it only over the internal
`homepage-internal` bridge network; `homepage` also joins `forge-net` for SWAG ingress.
`homepage-socketproxy` joins `homepage-internal` only — SWAG cannot resolve it.

---

## Configuration

Key `~/docker/homepage/docker-compose.yml` settings:

- `homepage`: `PUID=1000`, `PGID=1000`, `TZ=America/New_York`, `HOMEPAGE_ALLOWED_HOSTS=home.helmforge.me`
- `homepage-socketproxy`: tecnativa ACL env vars gate what the proxy exposes. Only
  `CONTAINERS=1` and `PING=1` are enabled; everything else (`POST`, `EXEC`, `BUILD`,
  `IMAGES`, `VOLUMES`, `NETWORKS`, `SECRETS`, `SYSTEM`, etc.) is `0`.

## Security notes

- **Root start, no cap_drop (accepted):** `homepage` starts as root to chown
  `/app/config` then drops to `PUID:PGID` via `gosu`; `cap_drop: ALL` would remove the
  `CAP_CHOWN`/`CAP_SETUID` needed for that drop, so `no-new-privileges` is the mitigation
  instead. `homepage-socketproxy` also runs as root — the tecnativa image has no
  configurable non-root uid and `docker.sock` access requires root or docker-group
  membership — but it does apply `cap_drop: ALL`.
- **`CONTAINERS=1` implies inspect access (accepted):** the tecnativa ACL can't separate
  container list/stats from full inspect (including the env array) — enabling one
  enables both. Risk is accepted because only `homepage` can reach the proxy
  (network-isolated on `homepage-internal`; SWAG cannot resolve it — verified). Full
  reasoning: `accepted-risks.md` — "homepage socket-proxy CONTAINERS=1 inspect/env
  disclosure".
- **`INFO` and `VERSION` disabled:** no Phase 1 widget needs `/info` (host topology
  disclosure) or `/version` (fingerprinting); homepage only calls `/_ping` and
  `/containers`.

---

## Operations

### Restart

```bash
cd ~/docker/homepage && docker compose down && docker compose up -d
```

### Health check

```bash
docker ps --filter name=homepage --format 'table {{.Names}}\t{{.Status}}'
docker exec swag curl -sI http://homepage:3000
```

### Logs

```bash
cd ~/docker/homepage && docker compose logs --tail=50
```

---

## Dependencies

| Depends on | Why |
|------------|-----|
| `homepage-socketproxy` | Read-only Docker API access for service cards |
| SWAG + `forge-net` | TLS termination, subdomain routing |

Nothing depends on homepage — it is a leaf dashboard service.

---

## Related docs

- [tools-stack.md](tools-stack.md) — same `no-new-privileges`-instead-of-`cap_drop`
  pattern for root-start images
