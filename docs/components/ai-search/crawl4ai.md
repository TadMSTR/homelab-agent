# Crawl4ai

Crawl4ai 0.9.3 — browser-based web content extraction service. Used by searxng-mcp for JS-heavy pages. Both Crawl4ai and Firecrawl do browser-based rendering now (Firecrawl gained a Playwright-backed rendering path in its own upgrade), so "static vs. dynamic" is no longer the dividing line between them — pick based on tier/use-case (see [firecrawl.md](firecrawl.md)) rather than treating Crawl4ai as the sole browser-rendering tier.

- **Version:** 0.9.3 — 0.9.3 is a security release (closes coordinated-disclosure advisories in the PDF-processing path and the Docker Playground UI) plus accumulated bug fixes; no behavioral changes affecting the setup documented below were identified.
- **Port:** `11235` (forge-net internal)
- **Compose:** `~/docker/crawl4ai/docker-compose.yml`
- **Network:** `forge-net`
- **No SWAG proxy** — internal use only
- **API token:** required — stored in `~/docker/crawl4ai/.env` (chmod 600), mirrored to `~/.claude-secrets/crawl4ai.env`

## Configuration

```yaml
environment:
  - CRAWL4AI_API_TOKEN=${CRAWL4AI_API_TOKEN}  # via env_file: .env
shm_size: "1g"   # required for browser rendering (Chromium shared memory)
```

`shm_size: 1g` is required. Without it, Chromium browser processes inside the container crash during page rendering.

## API Token

API token auth is enforced. Token is stored in two places:

| Path | Purpose |
|------|---------|
| `~/docker/crawl4ai/.env` | Loaded into container via `env_file` |
| `~/.claude-secrets/crawl4ai.env` | Read at runtime by `run-forge.sh` to set `CRAWL4AI_API_TOKEN` env var for searxng-mcp |

`run-forge.sh` reads the token at startup:
```bash
CRAWL4AI_API_TOKEN=$(grep '^CRAWL4AI_API_TOKEN=' ~/.claude-secrets/crawl4ai.env | cut -d= -f2-)
export CRAWL4AI_API_TOKEN
```

When rotating the token: update both files and redeploy crawl4ai + restart searxng-mcp sessions.

## Healthcheck

```
GET http://crawl4ai:11235/health
```

Returns 200 when the service is ready. searxng-mcp uses `CRAWL4AI_URL=http://crawl4ai:11235`.

## Security

| Finding | Status |
|---------|--------|
| H2: `CRAWL4AI_API_TOKEN` hardcoded in compose + run-forge.sh, committed to Gitea | Fixed — token rotated, moved to `env_file`, run-forge.sh updated to read from secrets file (commit `dbecf11`) |

## Related Docs

- [phase-5-user-stack-infra.md](../../phases/phase-5-user-stack-infra.md) — web search pipeline architecture
- [firecrawl.md](firecrawl.md) — complementary extraction service (also browser-capable; differentiator is tier/use-case, not static-vs-dynamic)
- [reranker.md](reranker.md) — result reranking (downstream of both)
