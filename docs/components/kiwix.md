# Kiwix

Offline content server for forge, serving ZIM archives of Wikipedia, Stack Overflow, and Arch Wiki. Runs as a single-container Docker stack on `forge-net`, consumed by SearXNG (as search engines) and `searxng-mcp` (as a fetch fast path). Eliminates external network traffic and scraper-blocking issues for high-value reference sites.

---

## Architecture

| Component | Image | Purpose |
|-----------|-------|---------|
| `kiwix` | `ghcr.io/kiwix/kiwix-serve` | Serves ZIM archives over HTTP |

Single container, no database or sidecar dependencies.

---

## Endpoints

| Endpoint | Bind | Purpose |
|----------|------|---------|
| `127.0.0.1:8292` | HTTP | Host-level access (mapped from container port 8080) |
| `kiwix:8080` | `forge-net` | Container-name DNS for SearXNG and other Docker services |

No SWAG proxy or public URL — localhost and `forge-net` only.

---

## ZIM Library

| ZIM file | Size | Content |
|----------|------|---------|
| `archlinux_en_all_maxi_2026-04.zim` | 34 MB | Arch Wiki (full) |
| `wikipedia_en_all_mini_2026-03.zim` | 12 GB | Wikipedia English (mini — text only, no images) |
| `stackoverflow.com_en_all_2023-11.zim` | 75 GB | Stack Overflow English (all Q&A) |

ZIM storage: `/mnt/data/kiwix/zim/` on `nvme0n1` `@data` btrfs subvolume, mounted read-only into the container.

The `--nodatealiases` flag is required so ZIM books are accessible by base name (e.g. `wikipedia_en_all_mini`) rather than date-suffixed paths.

---

## Configuration

### Docker stack

- Stack directory: `~/docker/kiwix/`
- Network: external `forge-net` (shared with SearXNG, SWAG, and other stacks)
- No appdata directory — kiwix-serve is stateless

### Resource limits

| Resource | Limit |
|----------|-------|
| Memory | 4 GB |
| CPU | 4 cores |

### SearXNG integration

Kiwix is registered as three separate search engines in SearXNG, reachable via `kiwix:8080` on `forge-net`. SearXNG sends search queries to kiwix-serve's built-in search API.

### searxng-mcp integration

The `searxng-mcp` fetch cascade includes a Kiwix fast path (gated by `KIWIX_URL` env var). Fetch requests for `en.wikipedia.org`, `stackoverflow.com`, and `wiki.archlinux.org` are intercepted before the Firecrawl/Crawl4AI tier cascade and served directly from Kiwix.

---

## Dependencies

| Depends on | Why |
|------------|-----|
| `/mnt/data/kiwix/zim/` (btrfs `@data`) | ZIM file storage |
| `forge-net` (Docker network) | Container-name DNS for SearXNG |

| Depends on Kiwix | Why |
|-------------------|-----|
| SearXNG | Offline search engines for Wikipedia, SO, Arch Wiki |
| `searxng-mcp` | Kiwix fast path in fetch cascade (`KIWIX_URL`) |

---

## Operations

### Restart

```bash
cd ~/docker/kiwix && docker compose down && docker compose up -d
```

### Health check

```bash
# Container status
docker inspect kiwix --format '{{.State.Status}}'

# HTTP check — returns kiwix-serve welcome page
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8292/
```

### Logs

```bash
docker logs kiwix
```

### Adding a ZIM file

1. Download the ZIM to `/mnt/data/kiwix/zim/`
2. Set ownership: `chown 1001:1001 /mnt/data/kiwix/zim/<file>.zim`
3. Restart the container — the `*.zim` glob in the command picks up all files automatically
4. If the new ZIM serves a host used by `searxng-mcp`, update the host-to-book mapping in `searxng-mcp/src/kiwix.ts`

---

## Security

- Runs as non-root (`1001:1001`)
- `cap_drop: ALL`, `no-new-privileges: true`
- Memory and CPU limits enforced
- ZIM volume mounted read-only — no write paths
- No authentication surface (serves public-domain content)
- `forge-net` exposure accepted: read-only public data, no write paths, CPU-bounded (audit ref: `kiwix-offline-2026-06` NE-02)

---

## Related docs

- [searxng-mcp README](https://github.com/TadMSTR/searxng-mcp) — Kiwix fast path documentation
- [SearXNG component doc](searxng.md) — SearXNG configuration including Kiwix engines
