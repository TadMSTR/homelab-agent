# Crawl4AI

Crawl4AI is a self-hosted web crawling and content extraction service. On claudebox it serves as the second-tier fetch fallback in the searxng-mcp fetch cascade — handling JS-heavy pages and cases where Firecrawl fails or returns poor content.

## Deployment

| Property | Value |
|----------|-------|
| Image | `unclecode/crawl4ai:0.8.6` |
| Port | `127.0.0.1:11235` (localhost only) |
| Network | `claudebox-net` |
| Appdata | `/opt/appdata/crawl4ai/` |
| Stack | `~/docker/crawl4ai/docker-compose.yml` |
| SWAG proxy | `crawl4ai.<internal-domain>` (Authelia forward auth) |

The container is bound to `127.0.0.1:11235` — external access is via SWAG only. The SWAG proxy is for operator use (testing, direct crawl requests); searxng-mcp reaches Crawl4AI via Docker DNS through `claudebox-net`.

## Role in searxng-mcp Fetch Cascade

`search_and_fetch`, `fetch_url`, and `search_and_summarize` use a three-tier fetch cascade:

```
1. Firecrawl    ← primary (JS rendering, clean markdown)
2. Crawl4AI     ← fallback if Firecrawl fails or returns empty content
3. rawFetch()   ← last resort (plain HTTP GET, basic HTML stripping)
```

Crawl4AI is invoked when Firecrawl returns an error or empty content. It uses the `markdown.raw_markdown` field from the Crawl4AI response — which gives clean, readable markdown without navigation cruft. Skipped silently if `CRAWL4AI_URL` is not set in the MCP environment.

The rawFetch() tier-3 fallback ensures a fetch never fails silently when both upstream services are unavailable.

## API Usage

Crawl4AI exposes an async crawl API. The searxng-mcp adapter:
1. POSTs a crawl request to `/crawl` with the target URL
2. Polls `/task/<task_id>` until status is `completed` or timeout
3. Extracts `result.markdown.raw_markdown` from the completed response

`task_id` values are validated against `^[a-zA-Z0-9_-]+$` before use in URL path construction — prevents SSRF via path traversal.

HTTP redirects in rawFetch() are blocked to prevent SSRF bypass via redirect chains to internal addresses.

## Configuration

Set `CRAWL4AI_URL` in the MCP server config:

```json
{
  "mcpServers": {
    "searxng": {
      "env": {
        "CRAWL4AI_URL": "http://crawl4ai:11235"
      }
    }
  }
}
```

If `CRAWL4AI_URL` is omitted, Crawl4AI is skipped in the fetch cascade and rawFetch() is used directly as the fallback.

## Related Docs

- [searxng-mcp.md](searxng-mcp.md) — MCP server that uses Crawl4AI as a fetch fallback
- [searxng.md](searxng.md) — SearXNG search backend
