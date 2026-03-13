# SearXNG

SearXNG is a self-hosted meta-search engine that aggregates results from multiple upstream search engines while keeping queries private. It's the search backend for LibreChat's web search pipeline — when you run a research query in LibreChat, SearXNG is what goes out and hits DuckDuckGo, Bing, Google, and the rest on your behalf.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, deployed as a standalone two-container stack. Two companion stacks — Firecrawl-simple and a reranker — extend SearXNG into a full search pipeline for the SearXNG MCP server (see [below](#the-search-pipeline)).

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

## The Search Pipeline

SearXNG handles the search itself, but two companion Docker stacks turn it into a complete search-and-retrieve pipeline for the [SearXNG MCP server](../../mcp-servers/README.md#searxng-mcp):

### Firecrawl-simple

[Firecrawl-simple](https://github.com/trieve/firecrawl-simple) (Trieve's lightweight fork of Firecrawl) scrapes web pages and returns clean markdown. The SearXNG MCP's `fetch_url` and `search_and_fetch` tools use it to retrieve full page content rather than just search snippets.

The stack has four containers: the API server, a background worker, a Puppeteer service for JS-heavy pages, and Redis for the job queue. All internal communication happens on a `firecrawl-internal` bridge network; only the API (port 3002) joins `claudebox-net` so the MCP server can reach it.

```yaml
services:
  firecrawl-api:
    image: trieve/firecrawl:v0.0.46
    container_name: firecrawl-api
    environment:
      - REDIS_URL=redis://firecrawl-redis:6379
      - PLAYWRIGHT_MICROSERVICE_URL=http://firecrawl-puppeteer:3000
      - PORT=3002
      - NUM_WORKERS_PER_QUEUE=4
      - USE_DB_AUTHENTICATION=false
    ports:
      - "127.0.0.1:3002:3002"
    networks:
      - claudebox-net
      - firecrawl-internal
    restart: unless-stopped

  firecrawl-worker:
    image: trieve/firecrawl:v0.0.46
    container_name: firecrawl-worker
    command: ["pnpm", "run", "workers"]
    networks:
      - firecrawl-internal
    restart: unless-stopped

  firecrawl-puppeteer:
    image: trieve/puppeteer-service-ts:v0.0.6
    container_name: firecrawl-puppeteer
    networks:
      - firecrawl-internal
    restart: unless-stopped

  firecrawl-redis:
    image: redis:alpine
    container_name: firecrawl-redis
    networks:
      - firecrawl-internal
    restart: unless-stopped
```

Auth is disabled (`USE_DB_AUTHENTICATION=false`) since this is internal-only. The port binding is on `127.0.0.1` — no reason to expose it outside the host.

### Reranker

A local cross-encoder model (ms-marco-MiniLM-L-12-v2) that reranks search results by relevance to the original query. SearXNG returns results ordered by its own scoring; the reranker re-sorts them so the most relevant results appear first before Claude sees them.

```yaml
services:
  reranker:
    build: .
    container_name: reranker
    environment:
      - RERANKER_MODEL=ms-marco-MiniLM-L-12-v2
    ports:
      - "127.0.0.1:8787:8787"
    networks:
      - claudebox-net
    restart: unless-stopped
```

Lightweight, runs on CPU, and makes a noticeable difference in result quality — especially for technical queries where the top SearXNG results aren't always the most relevant.

### How it fits together

```
Claude Code / LibreChat
  └── SearXNG MCP (PM2, port 8383)
        ├── search → SearXNG (port 8080) → reranker (port 8787)
        ├── fetch_url → Firecrawl-simple (port 3002)
        └── search_and_fetch → SearXNG → reranker → Firecrawl
```

All three backend services run on `claudebox-net`. The MCP server coordinates between them — the calling client just sees three clean tools.

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
- [SearXNG MCP server](../../mcp-servers/README.md#searxng-mcp) — MCP server that ties SearXNG, Firecrawl, and reranker together
- [SWAG](swag.md) — reverse proxy if you want `searxng.yourdomain` browser access
- [Docker compose file](../../docker/searxng/) — SearXNG stack compose
- [Firecrawl-simple](https://github.com/trieve/firecrawl-simple) — lightweight web scraper for page content
- [ms-marco-MiniLM](https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-12-v2) — cross-encoder model used by the reranker
