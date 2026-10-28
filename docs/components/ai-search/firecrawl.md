# Firecrawl (legacy stack — superseded)

> **Superseded as of 2026-09-05.** The stack described in this document (`firecrawl-simple`,
> image `trieve/firecrawl`) is **no longer the active Firecrawl** in the request path. All
> documented consumers have been cut over to a newer, upstream-based Firecrawl deployment.
> The legacy stack described below is not yet decommissioned: its containers still exist in
> the `crawler` stack (alongside Crawl4AI), but were found stopped on 2026-10-27 and receive no
> live traffic. Treat the
> content below as historical/reference material for the legacy stack, not as current
> architecture. See [firecrawl-v2.md](firecrawl-v2.md) for the current deployment.

Firecrawl v0.0.46 (legacy `firecrawl-simple` stack) — web scraping and content extraction service formerly used by searxng-mcp to fetch and clean page content from search results. Deployed as a 4-container stack with an isolated internal network.

- **Version:** 0.0.46
- **Compose:** `~/docker/firecrawl/docker-compose.yml`
- **Appdata:** `/opt/appdata/firecrawl/`
- **API endpoint:** `http://firecrawl-api:3002` (forge-net internal)
- **No SWAG proxy** — internal use only

## Stack

| Container | Networks | Role |
|-----------|----------|------|
| `firecrawl-api` | `forge-net`, `firecrawl-internal` | HTTP API — accepts scrape/crawl requests |
| `firecrawl-worker` | `firecrawl-internal` | Background job processor |
| `firecrawl-puppeteer` | `firecrawl-internal` | Headless browser (Puppeteer) for JS rendering |
| `firecrawl-redis` | `firecrawl-internal` | Job queue (Redis) |

`firecrawl-redis`, `firecrawl-worker`, and `firecrawl-puppeteer` are on `firecrawl-internal` only — they are not reachable from forge-net. Only `firecrawl-api` is reachable from other forge services.

## Configuration

No API authentication (`USE_DB_AUTHENTICATION=false`). Acceptable: no external exposure, forge-net only. Internal callers use `FIRECRAWL_API_KEY=placeholder-local` (any value is accepted when auth is disabled).

### COREPACK_INTEGRITY_KEYS=0 Workaround

Both `firecrawl-api` and `firecrawl-worker` set:
```yaml
environment:
  # WORKAROUND: pnpm v9.x Corepack key mismatch with trieve/firecrawl:v0.0.46
  # Remove when upgrading to v0.0.47+ or when upstream pnpm key is updated in image
  - COREPACK_INTEGRITY_KEYS=0
```

This disables pnpm binary integrity verification. Required for v0.0.46 to start; remove on upgrade if the upstream image has resolved the key mismatch.

## Usage (legacy — see notice above)

This describes how the legacy stack was used before the 2026-09-05 cutover. searxng-mcp
called firecrawl-api to extract clean text from URLs returned by SearXNG:

```
http://firecrawl-api:3002/v1/scrape  # gitleaks:allow
```

No API key header required (auth disabled). Response is markdown-formatted page content.

## Security

| Finding | Status |
|---------|--------|
| L2: No API auth | Accepted — forge-net only, no external exposure; any forge container could call it |
| M2: COREPACK_INTEGRITY_KEYS=0 without explanation | Fixed — comment added to compose (commit `dbecf11`) |

## Related Docs

- [phase-5-user-stack-infra.md](../../phases/phase-5-user-stack-infra.md) — build narrative, web search pipeline overview
- [crawl4ai.md](crawl4ai.md) — companion browser-rendering service
- [searxng-mcp.md](searxng-mcp.md#configuration) — the `adblock-proxy` container that filters
  searxng-mcp's fetches. It is defined in the `searxng` stack (moved there 2026-08-23 with its
  only consumer) and lives on the isolated `fetch-net` network, not in the `crawler` stack
