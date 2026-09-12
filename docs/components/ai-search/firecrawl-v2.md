# Firecrawl v2 (upstream, current)

Self-hosted upstream `firecrawl/firecrawl` — web scraping and content extraction, replacing
the [legacy `firecrawl-simple` stack](firecrawl.md), which is no longer in the request path.
Deployed as a second, parallel stack so the new backend could be built and measured against
before cutover; all three original consumers (a search-pipeline MCP, a job-enrichment MCP,
and a chat app's web-search tool) now point at it.

## What it is

Upstream Firecrawl self-host (pinned to a tagged release, not `latest` or `main` — the tag is
the only version whose compose contract and self-hosting docs are documented together). Five
containers: an API/worker, a Playwright-based renderer, Redis (rate-limit state), RabbitMQ
(short-lived queue hints), and Postgres (the job queue's actual system of record).

**Why the migration:** the prior stack was an unmaintained fork with no reproducible tagged
source and a measured tier-1 success rate under half that of the site's other scraping tier.
Upstream is active and ships a documented self-host path.

## Port / endpoint

Published on loopback only — the API is reachable at `127.0.0.1:<port>:3002` on the host,
never exposed externally. Everything else in the stack (renderer, queue, datastores) is
unpublished and reachable only from the API container itself.

**The API runs unauthenticated by design** (`USE_DB_AUTHENTICATION=false`), matching
upstream's own self-host default. Because there is no app-layer credential check, **network
placement is the access control** — the API container joins only the specific networks its
consumers sit on, not the platform-wide bridge network. A prior attempt to give the container
a route to loopback-only host services via a Docker host-gateway alias was removed after
review: it didn't reach its intended targets, but it did open an undisclosed path to every
externally-bound host service reachable from the Docker bridge. The lesson generalizes —
"network placement as access control" has to be verified end-to-end (what a declared network
actually reaches, and what else reaches in unexpectedly), not just asserted from the network
membership list.

## Configuration

Key environment variables:

| Variable | Purpose |
|---|---|
| `USE_DB_AUTHENTICATION` | `false` — matches the prior deployment; network placement is the real control |
| Redis / Postgres credentials | Freshly generated for this stack — **do not reuse credentials shared with other services**, even ones with a similar name, since that widens blast radius unnecessarily |
| Renderer image | Digest-pinned rather than tag-pinned — the upstream renderer publishes no semver tags at all, so a digest is the only stable reference |

Fire-engine (screenshots, page actions, stealth proxy, location/mobile emulation) is
closed-source and unavailable in any self-hosted deployment — this is verified against
upstream source, not assumed. A scrape request that includes page actions returns a clean
`HTTP 400` with a specific error code identifying the unsupported feature — it fails the
whole request rather than silently dropping the field, which matters for any client written
against the previous (cloud-capable) API surface. A client that used to send a
selector-based wait via `actions` needs to switch to a fixed-delay `waitFor` (milliseconds)
option instead.

**No private-IP filter exists at the scrape-engine layer.** A request targeting an internal
address proceeds to engine dispatch rather than being pre-filtered — it fails later, on
content negotiation. This is why the network-placement control above is the only thing
actually limiting what this API can reach, not a secondary layer.

**A response-shape guard every consumer needs:** a 404 origin still returns
`HTTP 200` / `success: true`, with the target's error-page text rendered as markdown in the
body and a separate status field carrying the real `404`. Any integration must assert on
that inner status field, not on the transport status or the top-level `success` flag, or a
failed fetch will look like a successful one.

## Dependencies

| Service | Role |
|---|---|
| API/worker | Scrape, crawl and map endpoints |
| Renderer (Playwright-based) | JS-rendered page fetching, with in-browser adblocking |
| Redis | Rate-limit state only — not persisted |
| RabbitMQ | Short-lived queue hints (message lifetime is shorter than the queue's own lock-reaper timeout) — not persisted, nothing of value to recover |
| Postgres | Job queue system of record — the only component that is persisted |

Consumers: a search-pipeline MCP server (tier-1 JS-rendered scraping), a job-search MCP
server (job description enrichment), and a self-hosted chat app's web-search tool. Each
reaches the API by container name over its own dedicated network rather than a shared
platform-wide one.

## Operations

```bash
# Health check
curl -s -X POST http://127.0.0.1:<port>/v2/scrape \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}'

# Container lifecycle
docker compose -f <stack-dir>/docker-compose.yml ps
docker logs <api-container-name> --tail 50
```

Only the Postgres queue is persisted, via a bind mount rather than a named Docker volume —
some backup tooling discovers stacks to protect by scanning compose files for a known bind
mount path, and is silently blind to named volumes. If your backup automation works the same
way, using a named volume for anything that must survive a rebuild will look like it's
covered when it silently isn't.

## scoped-mcp integration

Not an MCP server itself — this is a backend scraping service consumed by other MCP servers
and a chat app, none of which proxy it directly through scoped-mcp. See the consuming
services' own docs ([searxng-mcp.md](searxng-mcp.md), [jobsearch-mcp](../jobsearch-mcp.md))
for how each reaches it.

## Related Docs

- [firecrawl.md](firecrawl.md) — the legacy stack this replaces (still running, not yet
  decommissioned pending a bake-window measurement)
- [crawl4ai.md](crawl4ai.md) — the other scraping tier this pipeline falls back to
- [searxng-mcp.md](searxng-mcp.md) — the search-pipeline consumer and its version-flag pairing rule
