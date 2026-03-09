# Perplexica

Perplexica is a self-hosted alternative to Perplexity — an AI-powered search engine that uses SearXNG for meta-search across multiple engines and adds LLM-powered answer synthesis on top. It provides a conversational search interface where you ask a question, it searches the web, and returns a synthesized answer with cited sources.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, accessible at `perplexica.yourdomain` behind SWAG + Authelia.

## Why Perplexica

Sometimes you want a quick search-and-synthesize workflow without opening a full chat session in LibreChat. Perplexica fills that niche — ask a question, get a sourced answer, move on. It's lighter-weight than LibreChat for pure research queries where you don't need agents, memory, or multi-turn conversation.

The more important reason Perplexica is in the stack: it brought SearXNG along with it. SearXNG turned out to be more valuable than Perplexica itself — it's the meta-search backend that also powers [LibreChat's web search pipeline](librechat.md#web-search-pipeline). One SearXNG instance serves both Perplexica and LibreChat. No duplication, no extra API keys.

## What's in the Stack

The Perplexica stack deploys three containers:

| Container | Image | Purpose | RAM |
|-----------|-------|---------|-----|
| perplexica | itzcrazykns1337/perplexica:slim-latest | AI search UI + answer synthesis | ~200MB |
| searxng | searxng/searxng:latest | Meta-search engine (shared with LibreChat) | ~165MB |
| searxng-valkey | valkey/valkey:8-alpine | In-memory cache for SearXNG | ~15MB |

See [`docker/perplexica/docker-compose.yml`](../../docker/perplexica/docker-compose.yml) for the compose file.

### Network Topology

```
perplexica (your-network + perplexica-internal)
  └── → searxng:8080  (search queries)

searxng (your-network + perplexica-internal)
  └── → valkey:6379   (result caching)

LibreChat (your-network)
  └── → searxng:8080  (also uses SearXNG for web search pipeline)
```

Perplexica and SearXNG both join the shared Docker network so that other services (LibreChat, firecrawl-simple) can reach SearXNG by container name. Valkey is isolated on `perplexica-internal` — it only needs to talk to SearXNG.

## Prerequisites

- Docker CE + Compose
- An Anthropic or OpenAI API key (Perplexica needs an LLM for answer synthesis)
- SWAG + Authelia if you want subdomain access with SSO (optional — works on `localhost:3002` without a proxy)

## Configuration

### Perplexica

Perplexica stores its config at `/home/perplexica/data/config.json` inside the container (mapped to `/opt/appdata/perplexica/data/` on the host). On first startup, it creates a default config. You'll need to add your LLM provider credentials through the Perplexica UI settings page, or edit the config file directly:

```json
{
  "modelProviders": [
    {
      "name": "Anthropic",
      "type": "anthropic",
      "config": {
        "apiKey": "YOUR_ANTHROPIC_API_KEY"
      }
    }
  ],
  "search": {
    "searxngURL": "http://searxng:8080"
  }
}
```

The `searxngURL` must point to SearXNG's container name and port on the Docker network. Don't use `localhost` — Perplexica runs inside a container and `localhost` would refer to itself.

### SearXNG

SearXNG configuration lives at `/etc/searxng/settings.yml` inside the container (mapped from `/opt/appdata/perplexica/searxng/` on the host). The default settings work out of the box. Key things to consider:

The `SEARXNG_SECRET` environment variable is required — generate it with `openssl rand -hex 32` and put it in a `.env` file alongside the compose file.

Valkey runs as a tmpfs-backed ephemeral cache (`--save "" --appendonly no`). Search result caching is useful for performance but not critical — if Valkey restarts, SearXNG just re-fetches from upstream engines.

### SearXNG as a Shared Service

This is the key architectural decision: SearXNG is deployed as part of the Perplexica stack but serves double duty. LibreChat's web search pipeline (see [LibreChat docs](librechat.md#web-search-pipeline)) also points at `http://searxng:8080` for search queries. This works because SearXNG joins the shared Docker network.

If you're deploying LibreChat with web search but don't want Perplexica, you can pull SearXNG and Valkey out of this compose file into their own stack, or inline them into the LibreChat compose. The important thing is that SearXNG is reachable by container name from both consumers.

## Gotchas and Lessons Learned

**Use the `slim` image.** Perplexica publishes both a full image and a `slim` variant. The full image bundles a local embedding model for similarity search; the slim image skips it and relies on the LLM provider for everything. For a setup that already has qmd handling semantic search, the slim image saves ~2GB of disk and ~500MB of RAM.

**SearXNG rate limiting.** SearXNG aggressively rate-limits search engines by default to avoid getting IP-banned. If searches feel slow, check `/etc/searxng/limiter.toml` — you may want to tune the limits for a single-user setup where you're not hitting engines very hard.

**Perplexica port mapping.** Perplexica listens on port 3000 internally but the compose maps it to 3002 on the host to avoid conflicts with Dockhand (which also uses 3000). If you're proxying through SWAG, the proxy conf should point to port 3000 (the container port), not 3002 (the host mapping).

**Valkey vs Redis.** Valkey is a Redis fork maintained by the Linux Foundation after Redis changed its license. It's API-compatible — SearXNG doesn't know the difference. Using Valkey avoids the Redis license question entirely.

## Standalone Value

Perplexica + SearXNG is useful on its own as a self-hosted search tool with AI synthesis. No other components from this stack are required. If you just want a Perplexity alternative that runs locally, this is a clean two-command deployment (`docker compose up -d` plus adding your API key).

The more compelling standalone use is SearXNG itself. If you want private meta-search without AI synthesis, SearXNG works great on its own at `localhost:8080` or behind a reverse proxy.

## Further Reading

- [Perplexica GitHub](https://github.com/ItzCrazyKns/Perplexica)
- [SearXNG documentation](https://docs.searxng.org/)
- [Valkey project](https://valkey.io/)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where Perplexica fits in the three-layer stack
- [LibreChat](librechat.md) — uses the same SearXNG instance for its web search pipeline
- [SWAG](swag.md) — reverse proxy and SSL for `perplexica.yourdomain`
- [Authelia](authelia.md) — SSO protecting the Perplexica UI
- [Docker compose file](../../docker/perplexica/) — Perplexica stack compose
