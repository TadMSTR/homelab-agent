# LibreChat

LibreChat is the web-based chat interface for the stack — a self-hosted alternative to ChatGPT that supports multiple AI providers (Anthropic, OpenAI, Ollama, etc.), agent creation with tool access, persistent conversation memory, and built-in web search with RAG. It's the primary interface for interactive agent work that doesn't need the full Claude Desktop environment.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, behind SWAG + Authelia, accessible at `chat.yourdomain`.

## Why LibreChat

I needed a chat UI that could serve the household — something accessible from any device, not just the machine running Claude Desktop. LibreChat checked the boxes: multi-provider support so I'm not locked to one API, agent capabilities with MCP tool integration, and a conversation memory system that persists across sessions.

The alternatives I evaluated were Open WebUI and LobeChat. Open WebUI is excellent for Ollama-first setups but its external API provider support felt like an afterthought at the time. LobeChat looked polished but was thinner on agent tooling. LibreChat hit the right balance of features and active development.

## What's in the Stack

LibreChat deploys as three containers plus the web search pipeline (covered below):

| Container | Image | Purpose | RAM |
|-----------|-------|---------|-----|
| librechat | ghcr.io/danny-avila/librechat | App server | ~300MB |
| librechat-mongodb | mongo:7 | Conversation storage, user data | ~200MB |
| librechat-meilisearch | getmeili/meilisearch | Conversation search index | ~150MB |

All three join `claudebox-net` (the shared Docker network). No host port mappings — SWAG handles ingress.

## Configuration

LibreChat uses two config surfaces: a `.env` file for secrets and service URLs, and a `librechat.yaml` for feature configuration. The compose file is straightforward — see [`docker/librechat/docker-compose.yml`](../../docker/librechat/docker-compose.yml).

### librechat.yaml

The config file version matters. Web search support requires config version 1.2.6+. I'm running 1.3.5:

```yaml
version: 1.3.5
cache: true

balance:
  enabled: false
transactions:
  enabled: true

interface:
  webSearch: true

endpoints:
  anthropic:
    enabled: true
    models:
      - claude-sonnet-4-6
      - claude-opus-4-6
      - claude-haiku-4-5-20251001
  agents:
    capabilities:
      - "web_search"
      - "tools"
      - "actions"
      - "artifacts"

webSearch:
  searchProvider: "searxng"
  searxngInstanceUrl: "${SEARXNG_INSTANCE_URL}"
  scraperProvider: "firecrawl"
  firecrawlApiKey: "${FIRECRAWL_API_KEY}"
  firecrawlApiUrl: "${FIRECRAWL_API_URL}"
  rerankerType: "jina"
  jinaApiKey: "${JINA_API_KEY}"
  jinaApiUrl: "${JINA_API_URL}"
  safeSearch: 0

mcpSettings:
  allowedDomains:
    - "host.docker.internal"

mcpServers:
  qmd:
    type: streamable-http
    url: http://host.docker.internal:8181/mcp
```

The `mcpSettings.allowedDomains` entry is required for LibreChat to reach MCP servers running on the host (outside Docker). The `host.docker.internal` hostname resolves to the host's IP via Docker's `extra_hosts` mapping in the compose file.

### .env (relevant entries)

```bash
# Anthropic
ANTHROPIC_API_KEY=YOUR_ANTHROPIC_API_KEY

# Web search pipeline
SEARXNG_INSTANCE_URL=http://searxng:8080
FIRECRAWL_API_KEY=placeholder-local
FIRECRAWL_API_URL=http://firecrawl-api:3002
JINA_API_KEY=placeholder-local
JINA_API_URL=http://reranker:8787

# Meilisearch (conversation search)
MEILI_MASTER_KEY=YOUR_GENERATED_KEY
```

The `FIRECRAWL_API_KEY` and `JINA_API_KEY` values are placeholders — firecrawl-simple runs with `USE_DB_AUTHENTICATION=false` and the reranker wrapper ignores auth headers. They just need to be non-empty for LibreChat to accept the config.

## Web Search Pipeline

This is the most interesting part of the LibreChat setup. LibreChat's built-in web search feature provides a full pipeline — search, scrape full page content, rerank by relevance — rather than just returning search snippets. The entire pipeline is self-hosted with zero recurring API costs.

### Why Not MCP-Based Search?

An MCP tool calling SearXNG would only return search snippets (titles, URLs, brief descriptions). LibreChat's built-in web search goes further: it takes the search results, scrapes the full page content from each URL, converts it to markdown, then reranks everything by relevance before feeding it to the model. Much better context for the model to work with.

### Pipeline Components

The pipeline has three stages, each handled by a separate service:

**1. Search — SearXNG** (`http://searxng:8080`)

SearXNG was already in the stack for Perplexica. LibreChat points at the same instance. No additional deployment needed. It performs meta-search across multiple search engines and returns URLs + snippets.

**2. Scrape — firecrawl-simple** (`http://firecrawl-api:3002`)

This is where the decision-making got interesting. Mainline Firecrawl requires five containers (API, Playwright, Redis, RabbitMQ, Postgres) with 8GB+ recommended RAM for the API server alone, and has known stability issues with self-hosted deployments — RabbitMQ timing failures, schema drift, corepack errors.

The Trieve fork [firecrawl-simple](https://github.com/devflowinc/firecrawl-simple) strips out billing, AI features, and Supabase, replaces Playwright with Puppeteer, and uses prebuilt Docker images. It speaks the same Firecrawl v1 API that LibreChat expects, so it's a drop-in replacement. Four containers instead of five, roughly 1.1GB total RAM.

See [`docker/firecrawl-simple/docker-compose.yml`](../../docker/firecrawl-simple/docker-compose.yml) for the compose file.

**3. Rerank — FlashRank via custom Jina wrapper** (`http://reranker:8787`)

LibreChat only supports Jina and Cohere as reranker providers natively. There's no self-hosted reranker option (there's an [open discussion](https://github.com/danny-avila/LibreChat/discussions/9102) but nothing merged). To avoid recurring API costs, I built a small FastAPI wrapper that exposes Jina's `/v1/rerank` endpoint format but runs FlashRank under the hood.

FlashRank is an ONNX-optimized, CPU-only reranking library — about 4MB for the model, ~110MB RAM at runtime. The wrapper is ~115 lines of Python. LibreChat points `jinaApiUrl` at it and sees a standard Jina API. Zero cost, zero external dependencies.

The wrapper lives at [`docker/reranker/`](../../docker/reranker/) with a custom Dockerfile and the FastAPI source.

### Network Topology

```
LibreChat (claudebox-net)
  ├── → searxng:8080         (search queries)
  ├── → firecrawl-api:3002   (page scraping)
  └── → reranker:8787        (result reranking)

firecrawl-api (claudebox-net + firecrawl-internal)
  ├── → firecrawl-puppeteer:3000  (headless browser, internal only)
  ├── → firecrawl-redis:6379      (job queue, internal only)
  └── firecrawl-worker            (background jobs, internal only)
```

Only `firecrawl-api` joins `claudebox-net`. All firecrawl internal services (puppeteer, redis, worker) are isolated on a `firecrawl-internal` bridge network. No host port mappings anywhere — all communication is Docker DNS.

### Total Resource Cost

The full web search pipeline adds about 1.2GB RAM on top of LibreChat's base footprint (SearXNG was already running for Perplexica):

| Component | RAM |
|-----------|-----|
| SearXNG | ~165MB (shared with Perplexica) |
| firecrawl-simple (4 containers) | ~1.1GB |
| FlashRank reranker | ~110MB |

## MCP Integration

LibreChat supports MCP servers for agent tool access via the `mcpServers` block in `librechat.yaml`. There are two patterns for how MCP servers connect:

**Host-level services** (like qmd) run outside Docker and are reached via `host.docker.internal`. The `extra_hosts` mapping in the compose file resolves that hostname to the host gateway IP, and `mcpSettings.allowedDomains` whitelists it for MCP connections.

**Sidecar containers** run as additional services in the LibreChat compose stack, on the same Docker network. This is the pattern for backrest-mcp and grafana-mcp — each wraps an MCP server and exposes a `streamable-http` endpoint that LibreChat reaches by container name. The backrest-mcp sidecar uses [supergateway](https://github.com/supercorp-ai/supergateway) to wrap the stdio-based backrest-mcp-server and expose it over HTTP. The grafana-mcp sidecar uses Grafana's official MCP image with HTTP transport enabled.

Sidecar containers are the right pattern when the MCP server doesn't already run as a persistent host-level service, or when you want the MCP server lifecycle tied to the LibreChat stack.

## Token Usage Tracking

LibreChat has two related systems for token tracking: transactions (logging) and balance (enforcement). They're independent — you can log everything without enforcing credit limits.

With `transactions.enabled: true`, every API call writes a record to the `Transactions` collection in MongoDB capturing prompt tokens, completion tokens, model, cost, and user. With `balance.enabled: false`, there's no credit enforcement — usage is tracked but never blocked. This is the right setup for a personal/household instance where you want visibility without artificial limits.

The transaction data in MongoDB can be queried for dashboards (see the Grafana integration notes below) or exported for cost analysis. LibreChat also exposes Prometheus-compatible metrics via an OpenMetrics endpoint for real-time monitoring.

**Known issue (as of v0.8.3-rc2):** Agent transactions record the agent ID (e.g., `agent_8aWN5tLYRAdtV8knVWmod`) in the model field instead of the underlying model name. This causes incorrect pricing lookups for agent interactions. Tracked in [#11978](https://github.com/danny-avila/LibreChat/issues/11978). If you're building cost dashboards, filter or map agent IDs to their configured models until this is fixed.

## Gotchas and Lessons Learned

**Config version matters.** Web search support was added in LibreChat config version 1.2.6. If you're on an older `librechat.yaml` version, the `webSearch` block will be silently ignored. Bump to 1.2.6+ (I'm on 1.3.5).

**Meilisearch needs MEILI_MASTER_KEY.** Without it, LibreChat logs `[indexSync] error Meilisearch configuration is missing` and conversation search doesn't work. Add `MEILI_MASTER_KEY` to both the meilisearch service environment and the shared `.env` file.

**Corepack signature bug in firecrawl-simple.** The trieve/firecrawl image fails on startup with a `Cannot find matching keyid` error. Fix: set `COREPACK_INTEGRITY_KEYS=0` on both `firecrawl-api` and `firecrawl-worker` containers. This disables corepack's package manager integrity verification — not ideal, but it's a known issue with the image.

**Wrong env var names.** LibreChat's web search uses `SEARXNG_INSTANCE_URL`, not `SEARXNG_URL`. And the feature is enabled in `librechat.yaml` via `interface.webSearch: true`, not via `SEARCH=true` in the env. If search isn't working, double-check variable names against the [LibreChat docs](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/web_search).

**FlashRank model download on first start.** The reranker container downloads the model (~22MB) on first startup. Subsequent restarts use the cached copy inside the container layer. If the container image is rebuilt or pulled fresh, it re-downloads.

**Pin firecrawl-simple versions.** I'm on v0.0.46 (api/worker) and v0.0.6 (puppeteer). These are stable. Check [firecrawl-simple releases](https://github.com/devflowinc/firecrawl-simple) before upgrading — breaking changes happen.

## Standalone Value

The LibreChat stack is useful on its own, even without the rest of the homelab-agent platform. At minimum, you get a self-hosted multi-provider chat UI behind authentication. Add the web search pipeline and you have a self-hosted Perplexity-like experience with full page scraping and reranking — zero API costs beyond the LLM provider itself.

You don't need the CLAUDE.md hierarchy, memsearch, or PM2 agents to get value from this component. It works as a standalone chat interface for anyone in the household with a browser.

## Further Reading

- [LibreChat documentation](https://www.librechat.ai/docs)
- [firecrawl-simple (Trieve fork)](https://github.com/devflowinc/firecrawl-simple)
- [FlashRank](https://github.com/PrithivirajDamodaran/FlashRank)
- [LibreChat web search config reference](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/web_search)
- [LibreChat reranker discussion #9102](https://github.com/danny-avila/LibreChat/discussions/9102)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where LibreChat fits in the three-layer stack
- [MCP servers reference](../../mcp-servers/README.md) — qmd config for LibreChat's MCP integration
- [PM2 services](../../pm2/ecosystem.config.js.example) — qmd and other services LibreChat depends on
- [Docker compose files](../../docker/librechat/) — LibreChat stack compose and config
- [firecrawl-simple compose](../../docker/firecrawl-simple/) — web scraper for the search pipeline
- [Reranker source + Dockerfile](../../docker/reranker/) — FlashRank wrapper referenced above
