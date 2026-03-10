# SearXNG

SearXNG is a self-hosted meta-search engine that aggregates results from multiple upstream search engines while keeping queries private. It's the search backend for LibreChat's web search pipeline — when you run a research query in LibreChat, SearXNG is what goes out and hits DuckDuckGo, Bing, Google, and the rest on your behalf.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, deployed as a standalone two-container stack.

## Why SearXNG

The obvious reason is privacy — no search provider sees a coherent history of your queries. The more practical reason for this stack is that LibreChat's built-in web search pipeline requires a search provider, and SearXNG is the only self-hosted option that fits cleanly. No API keys, no rate limits, no per-query costs.

SearXNG was originally deployed as part of a Perplexica stack (an AI-powered search UI, now called Vane). Perplexica added a conversational search interface on top of SearXNG but was eventually removed — LibreChat's research agent covers that use case directly, with better model access, tool integration, and token tracking. SearXNG stayed; Perplexica didn't.

## What's in the Stack

Two containers, minimal footprint:

| Container | Image | Purpose | RAM |
|-----------|-------|---------|-----|
| searxng | searxng/searxng:latest | Meta-search engine | ~165MB |
| searxng-valkey | valkey/valkey:8-alpine | In-memory result cache | ~15MB |

See [`docker/searxng/docker-compose.yml`](../../docker/searxng/docker-compose.yml) for the compose file.

### Network Topology

```
LibreChat (claudebox-net)
  └── → searxng:8080   (search queries, JSON format)

searxng (claudebox-net + searxng-internal)
  └── → searxng-valkey:6379   (result caching)
```

SearXNG joins the shared Docker network (`claudebox-net`) so LibreChat can reach it by container name. Valkey is isolated on a `searxng-internal` bridge — it only needs to talk to SearXNG.

## Prerequisites

- Docker CE + Compose
- A shared Docker network that LibreChat is also on — create with `docker network create claudebox-net` if it doesn't exist yet

No API keys or external accounts needed.

## Configuration

### SearXNG settings

SearXNG configuration lives at `/etc/searxng/settings.yml` inside the container, mapped from `/opt/appdata/searxng/searxng/` on the host. The defaults work for most purposes. Two things to set explicitly:

**Secret key** — Required. Generate with `openssl rand -hex 32` and set as `SEARXNG_SECRET` in a `.env` file alongside the compose file. SearXNG won't start without it.

**JSON format** — LibreChat queries SearXNG with `format=json`. Make sure `json` is in the enabled formats list in `settings.yml`:

```yaml
search:
  formats:
    - html
    - json
```

### Valkey

Valkey runs as an ephemeral cache with no persistence (`--save "" --appendonly no`). If it restarts, SearXNG just re-fetches from upstream engines — no data loss, slight latency on the first query after restart. This is intentional: you don't want search result caches persisting to disk.

### Compose sketch

```yaml
services:
  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    environment:
      - SEARXNG_SECRET=${SEARXNG_SECRET}
    volumes:
      - /opt/appdata/searxng/searxng:/etc/searxng
    networks:
      - claudebox-net
      - searxng-internal
    restart: unless-stopped

  searxng-valkey:
    image: valkey/valkey:8-alpine
    container_name: searxng-valkey
    command: valkey-server --save "" --appendonly no
    networks:
      - searxng-internal
    restart: unless-stopped

networks:
  claudebox-net:
    external: true
  searxng-internal:
    driver: bridge
```

## Integration with LibreChat

LibreChat's web search pipeline points at `http://searxng:8080`. This works because both containers share `claudebox-net` and Docker resolves container names via DNS on that network.

The relevant LibreChat config in `.env`:

```
SEARXNG_INSTANCE_URL=http://searxng:8080
```

Web search is enabled in `librechat.yaml` via the interface block. See the [LibreChat component doc](librechat.md#web-search-pipeline) for the full pipeline breakdown.

## Gotchas and Lessons Learned

**Use the env var name exactly.** LibreChat uses `SEARXNG_INSTANCE_URL`, not `SEARXNG_URL`. If web search isn't returning results, check this first.

**JSON format must be explicitly enabled.** SearXNG ships with JSON disabled by default in recent versions. LibreChat queries with `format=json` — if JSON isn't in your `settings.yml` formats list, every search request returns a 400. Add it explicitly.

**Rate limiting is tuned for public instances.** SearXNG's default rate limits assume it's serving many users. On a single-user homelab, you're unlikely to trigger upstream bans. If searches feel slow, check `limiter.toml` — you may want to relax the limits.

**Valkey vs Redis.** Valkey is a Redis fork maintained by the Linux Foundation after Redis changed its license in 2024. It's API-compatible — SearXNG doesn't know the difference. Using Valkey sidesteps the license question without any functional tradeoff.

**No host port mapping needed.** If SearXNG is only consumed by other Docker containers, there's no need to expose port 8080 to the host. Keep it internal-only unless you want direct browser access.

## Standalone Value

SearXNG is useful entirely on its own as a private search interface — add a port mapping and point your browser at it. It also supports browser search engine integration so you can set it as your default from the address bar.

The Valkey cache is optional. SearXNG functions without it; it just re-fetches on every query. For a single-user instance with modest query volume, the difference is negligible.

## Further Reading

- [SearXNG documentation](https://docs.searxng.org/)
- [SearXNG GitHub](https://github.com/searxng/searxng)
- [Valkey project](https://valkey.io/)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where SearXNG fits in the three-layer stack
- [LibreChat](librechat.md) — primary consumer of SearXNG for web search
- [SWAG](swag.md) — reverse proxy if you want `searxng.yourdomain` browser access
- [Docker compose file](../../docker/searxng/) — SearXNG stack compose
