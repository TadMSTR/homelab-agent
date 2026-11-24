# searxng-mcp

An MCP server for private web search via a self-hosted [SearXNG](https://github.com/searxng/searxng)
instance — search with local ML reranking, full-page fetch via a Firecrawl/Crawl4AI/raw-HTTP
cascade, and a domain capability database that learns which fetch tier works for which host. See
the [project README](https://github.com/TadMSTR/searxng-mcp) for the full tool/architecture
reference; this doc covers forge's deployment of it.

- **Version:** v4.1.0, for all four images from this repo, each digest-pinned in compose —
  `searxng-mcp`, `searxng-mcp-adblock-proxy` and `searxng-mcp-reranker` in the `searxng` stack,
  and `searxng-mcp-playwright-adblock` in the Firecrawl stack (container
  `firecrawl-v2-playwright`, the renderer behind Firecrawl's fetches) — verified in `docker ps`
  2026-11-23. The four are bumped together, so they always run the same release
- **Runs as:** Docker container in the `searxng` stack (`~/docker/searxng/docker-compose.yml`),
  co-located with SearXNG itself since a 2026-08-23 stack consolidation. As of the v3.26.0
  cutover the container runs a published, digest-pinned image
  (`ghcr.io/tadmstr/searxng-mcp:v4.1.0`) rather than a local build off repo main — a supply-chain
  improvement as much as a convenience: the image is now reproducible from a tagged release
  instead of whatever commit happened to be checked out at build time
- **Endpoint:** `http://127.0.0.1:8504` — bearer-authed
- **Transport:** streamable-http
- **Agents:** all agent manifests (developer, fleet, jobsearch, research, security, sysadmin,
  writer) and the four desktop-client profiles — every client goes through this one container
  since 2026-11-19

## What changed 2026-08-19

This service was a bare PM2 process on `127.0.0.1:8504` with **no authentication** for its
entire life, which was survivable only because it was loopback-bound. Containerising it forces a
`0.0.0.0` bind so it resolves by container name — deleting the only thing protecting an
arbitrary-URL `fetch_url` tool and a destructive `clear_cache` tool. So bearer auth shipped
*before* the container did, not alongside it: the auth landed in v3.18.0's first two phases, and
only once every agent manifest carried the bearer header did the cutover flip the socket from the
PM2 process to the container. Zero outage, each step independently verifiable — the manifests'
header was harmless against the old unauthenticated PM2 instance for the time both existed.

The PM2 process (`~/scripts/run-searxng-mcp-http.sh`) is **stopped, deleted, and pm2-saved** —
it no longer exists. There is one instance of this service now, not two. As of 2026-11-19 the
launcher scripts themselves are gone too — see [What changed 2026-11](#what-changed-2026-11-v3310--v410).

## What changed 2026-11 (v3.31.0 → v4.1.0)

Five releases in five days, from a backlog programme that worked through searxng-mcp's open
tickets. The MCP tool surface didn't change in a way any client had to act on. Per release, as it
affects this deployment (full detail in the
[project CHANGELOG](https://github.com/TadMSTR/searxng-mcp/blob/main/CHANGELOG.md)):

- **3.31.0 (2026-11-16)** — `crawl_site` stays under the start URL's path (pass
  `include_path: "/"` for the old whole-site behaviour), `fetch_url` stops answering most
  github.com pages with the repo README, empty optional arguments count as omitted, zod 4.
- **3.31.1 (2026-11-17)** — fixes a 3.31.0 regression where the string `"false"` read as `true`
  for `expand` and `same_domain_only`; `GITHUB_TOKEN` is now sent only to URLs shaped like the
  GitHub fast path's repository endpoints. (This container sets no `GITHUB_TOKEN`, so the token
  change is moot here.)
- **3.32.0 (2026-11-17)** — the silent-failure release: places that reported success while doing
  nothing. `adblock-proxy` used to install an empty rule set as if it were good and pass all
  traffic; it now refuses an empty or incomplete load and has a `GET /health` (see
  [Port / Endpoint](#port--endpoint)). `same_domain_only` now holds on every crawl strategy, not
  just BFS — this deployment crawls through Firecrawl, so the flag had been doing nothing here.
  Upstream error text relayed into logs, `domain_stats` and NATS events is bounded and scrubbed of
  URL credentials.
- **Stack healthchecks (2026-11-19, no release)** — compose-only change. `searxng`, the reranker
  and the Firecrawl stack's services gained healthchecks, `firecrawl-v2-api` now waits for its
  dependencies to be healthy, and searxng-mcp gained `depends_on: searxng-dragonfly:
  service_healthy`. `playwright-adblock` was brought up to the same release as the other three
  images. The old PM2-era launcher scripts were retired; desktop clients use the container, with
  the same bearer header as the agent manifests.
- **4.0.0 (2026-11-19)** — the dependency-major release (OpenTelemetry SDK, jsdom 31, vitest 5).
  Breaking only for npm consumers: Node `^22.22.2 || ^24.15.0 || >=26.0.0` is required, and the
  main and `adblock-proxy` images now run Node 24. The main image finally ships `domains.json`
  (it had been missing from every container, so the llms.txt fast path never fired); the server
  logs a `domains: llms_txt=N boost=N block=N profiles=N` line on load. `adblock-proxy` retries
  a failed startup load (1, 2, 4, 8, 16 minutes, then every `ADBLOCK_RETRY_MAX_MINUTES`, default
  30) instead of running unfiltered until the weekly refresh.
- **4.1.0 (2026-11-20)** — observability and usage data. New metrics for crawls, fallbacks
  (`searxng_degrade_total`) and reranker scores (`searxng_rerank_top_score`);
  `searxng_errors_total` now counts every tool's failures, not only search's; spans record which
  fetch tier served a page (`fetch.tier_served`) and whether it was a cache hit. A caller's W3C
  `traceparent` is accepted after the bearer check — inert here until scoped-mcp sends one
  (vikunja#1576). The GitHub fast path now says why it failed, and file URLs fall back to the
  normal cascade. No new environment variables.

## Port / Endpoint

`127.0.0.1:8504`, bearer token required on every request except `GET /health`
(`Authorization: Bearer ${SEARXNG_MCP_TOKEN}`). **There is no unauthenticated fallback** — unset
the token and every agent gets 401. One shared token authenticates access to the server as a
whole; searxng-mcp has no per-caller authorization model, so per-agent tokens would imply scoping
the server doesn't implement. Tool-level scoping (e.g. denying `clear_cache` to a given agent)
stays at the scoped-mcp proxy layer, not here.

`GET /health` is exempt by design — it's the container healthcheck, takes no input, and its
response carries no secrets:

```json
{"status": "ok", "cache": "up", "sessions": 3}
```

It returns **503 when Valkey is unreachable**, so a cache outage marks the container unhealthy
even though the server itself fails soft (cache miss → serve live, doesn't error). `restart:
unless-stopped` does not act on container health, so nothing auto-restarts as a result — this
surprises people, worth knowing before assuming a 503 means the process is down. Nothing needs
to: the cache client is dropped on any error and rebuilt on the next call (including the next
`/health`), so the container goes healthy again by itself once Valkey is back — confirmed live
on 2026-11-19 with no restart. Nothing alerts on an unhealthy container yet either
(vikunja#1564).

Since 2026-11-19 searxng-mcp also has `depends_on: searxng-dragonfly: service_healthy`, so on
a full stack restart it no longer starts before its cache. Treat that as startup ordering only:
the dragonfly healthcheck is an unauthenticated `ping`, which passes on a `NOAUTH` reply, so it
proves the port answers and nothing more.

`adblock-proxy` has its own `GET /health` since v3.32.0, and its image's `HEALTHCHECK` is what's
in force (the compose file deliberately adds no override). `200` with `status` `ok`, or
`partial` when the rule set is missing some configured lists (still filtering); `503` with
`no_filters` when no usable rule set is loaded, or `stale` when refreshes have kept failing.
Treating `partial` as unhealthy would mark the container down for a whole refresh interval
after a single list's outage, so alert on the `status` field rather than adding a stricter
check.

## Configuration

| Variable | Purpose |
|----------|---------|
| `SEARXNG_MCP_AUTH_TOKEN` | Bearer token clients must present; injected via manifest env from `SEARXNG_MCP_TOKEN` |
| `SEARXNG_MCP_TRANSPORT` / `SEARXNG_MCP_HOST` / `SEARXNG_MCP_PORT` | Fixed to `http` / `0.0.0.0` / `8504` in the container — the `8504:8504` host publish depends on the port override matching |
| `DOMAIN_DB_SNAPSHOT_DIR` / `DOMAIN_DB_SNAPSHOT_RETENTION` | Domain-capability-DB snapshot durability (`/snapshots`, retention 60) |
| Service URLs (`SEARXNG_URL`, `FIRECRAWL_URL`, `RERANKER_URL`, `CRAWL4AI_URL`, `OLLAMA_URL`, `KIWIX_URL`, `ADBLOCK_PROXY_URL`, `NATS_URL`) | See `docker-compose.yml` — several of these are easy to get wrong across the container/host boundary, see below |
| `NATS_USER` / `NATS_SUBJECT_PREFIX` | `searxng-mcp` / `events.searxng` |

Secrets: `~/.secrets/searxng-mcp.env`, chmod 600. Deliberately **not** `forge.env` — that
would inject `ANTHROPIC_API_KEY` and `GITEA_TOKEN` into a container with no use for them.

**Three dependency-URL traps**, worth knowing before debugging a "why can't it reach X":

- **Kiwix** — container port is **8080**, not the published host port (`8292`).
  `http://kiwix:8292` fails; `http://kiwix:8080` works.
- **Ollama** — traffic must go via **`ollama-queue-proxy:11435`**, not `ollama:11434` directly.
  Going straight to `ollama` bypasses the queue proxy and the `OLLAMA_API_KEY` gate it enforces.
- **`adblock-proxy`** — this used to be documented as a compose service alias fronting a
  differently-named container. That's no longer true: since the v3.26.0 cutover it's a real,
  published container named `adblock-proxy`. The reason searxng-mcp joins a second network
  (`fetch-net`, alongside `forge-net`) isn't an alias-resolution quirk anymore either — it's
  because `adblock-proxy` and the solver-tier service (Byparr — see below) both live on
  `fetch-net` specifically so they're *not* reachable from the wider `forge-net` population.
  Both are unauthenticated services that will act on whatever URL they're handed, so they get the
  smallest network that still lets searxng-mcp reach them.
- **Byparr (solver tier)** — same `fetch-net` isolation as `adblock-proxy`, same reasoning. See
  [Solver Tier](#solver-tier-byparr) below and [byparr.md](byparr.md).

## Dependencies

| Service | Required | Purpose |
|---------|----------|---------|
| SearXNG | Yes | Underlying search engine |
| Firecrawl | Yes | Tier-1 full-page fetch |
| Valkey (`searxng-dragonfly`) | Recommended | Result/fetch caching + domain capability DB. Server degrades gracefully (no caching) if unreachable, but the domain DB — and therefore data-driven tier routing — needs it |
| Crawl4AI, Ollama, Kiwix, reranker | Optional | Tier-2 fetch fallback, query expansion/summarization, offline-doc fast path, result reranking — each degrades independently when unset/unreachable |
| Byparr | Optional | Challenge-solver tier for pages a standard fetch tier can't get past (JS/Cloudflare-style challenges). Degrades to "fetch fails" for challenge-gated pages when unset — see [Solver Tier](#solver-tier-byparr) below and [byparr.md](byparr.md) |

The reranker deserves its own callout: it's a shared sidecar, not exclusive to searxng-mcp. A
second, independent consumer (a chat UI, wired directly to the reranker's Jina-compatible
`/v1/rerank` endpoint) also depends on it, with no health surface of its own for that second
consumer to check. The reranker has no auth — its mitigation is publishing loopback-only rather
than network isolation, since a second, out-of-stack consumer needs to reach it and a
narrow shared network wouldn't cover that case the way it does for `adblock-proxy`/Byparr above.
See [reranker.md](reranker.md).

## Solver Tier (Byparr)

searxng-mcp's fetch cascade normally runs Firecrawl → Crawl4AI → raw HTTP, in that order, falling
back a tier whenever the one before it can't extract usable content. The solver tier sits outside
that ladder: it's only invoked when a fetch attempt comes back as a bot-challenge page (a
JS-executing "checking your browser" interstitial) rather than a normal failure. In that case,
searxng-mcp hands the URL to Byparr, which drives a real headless browser through the challenge
and returns cookies/HTML the caller can use to retry the fetch.

Configuration is two env vars: `SOLVER_ENABLED` (gate — off means challenge pages just fail like
any other unreachable fetch) and `SOLVER_URL` (pointing at the Byparr container on `fetch-net`).
Byparr has no host-published port and no auth of its own; see
[byparr.md](byparr.md#network-placement--why-its-isolated) for why that's an acceptable trade —
short version, it's isolated on `fetch-net`, a small network kept off `forge-net` (see
[fetch-net](#fetch-net) for who else is on it).

The solver tier is deliberately a last resort, not a default: spinning up a full browser session
per request is far more expensive than any other tier, so it only runs when everything cheaper
has already failed.

## Hardening

- `user: 1000:1000`, `cap_drop: [ALL]`, `no-new-privileges:true`
- `read_only: true` root filesystem + tmpfs `/tmp` — all state lives in Valkey; the only writable
  path is the bind mount `/opt/appdata/searxng/domain-db-snapshots` → `/snapshots`. If something
  ever turns out to need a writable root, find out *what* before dropping this flag.
- `mem_limit: 2g`, `cpus: 2.0`, `ulimits: core: 0`
- Networks: `forge-net` and `fetch-net` — the latter exists so searxng-mcp can reach
  `adblock-proxy` and Byparr without either being reachable from `forge-net`'s much larger
  population of containers. `firecrawl-v2-api` from the Firecrawl stack is on it too (see
  below)

### fetch-net

`fetch-net` is an unowned, external network. It was created by hand
(`docker network create fetch-net`) and is declared `external` in both this stack and
`~/docker/firecrawl-v2/`. The two compose files attach `searxng-mcp`, `adblock-proxy` and
`byparr` from this stack, and `firecrawl-v2-api` from the Firecrawl stack.

It used to be the searxng-owned `searxng_fetch-net` (and before that `crawler_fetch-net`).
When one stack owned it, a `docker compose down` or recreate of the searxng stack removed
the network and dropped `firecrawl-v2-api`'s endpoint with it. With neither stack owning it,
recreating either one leaves the other's attachment in place (vikunja#1164). It is not
`--internal`: Byparr and `adblock-proxy` fetch the internet over it.

## Concurrent-write behaviour

Both the (former) PM2 process and this container wrote the same Valkey domain DB (`domain:*`).
v3.17.0's Lua compare-and-set write primitive makes torn writes across processes structurally
impossible, but conflict retries are bounded (3 attempts) with a `cas_exhausted` counter exposed
if that budget is ever exceeded. This was relevant during the roughly one-hour window both
instances existed side by side during cutover; it isn't a live concern now that PM2 is gone and
there's a single writer again — noted here only so a future reader doesn't go looking for a
concurrency issue that no longer applies.

## Operations

```bash
# Status
docker compose -f ~/docker/searxng/docker-compose.yml ps

# Logs
docker compose -f ~/docker/searxng/docker-compose.yml logs -f searxng-mcp

# Restart (e.g. after a token rotation — env_file changes need a recreate, not a bare restart)
docker compose -f ~/docker/searxng/docker-compose.yml up -d --force-recreate searxng-mcp

# Manual health check
curl -s http://127.0.0.1:8504/health

# Manual authenticated call
curl -s -H "Authorization: Bearer $SEARXNG_MCP_TOKEN" http://127.0.0.1:8504/mcp
```

### Rollback

There is **no PM2 rollback any more**. The PM2 entry was deleted at cutover, and on 2026-11-19
the launcher scripts and the saved PM2 recreate file were removed as well — a PM2 instance
would also have been unauthenticated, which was the whole problem. Rolling back now means
restoring the previous digest-pinned image line in `docker-compose.yml` and recreating the
container. Keep the four images from this repo on the same release when you do.

## scoped-mcp Integration

All 7 agent manifests carry `Authorization: Bearer ${SEARXNG_MCP_TOKEN}`, resolved from
`/opt/appdata/agents/<type>/.env`. Since 2026-11-19 the four desktop-client profiles use the
same `mcp_proxy` block to `http://127.0.0.1:8504/mcp`, replacing a stdio launcher that had
handed the whole host env file and NATS credentials to a child process. Tool scoping (e.g. `clear_cache` denylisting) is enforced at
the proxy layer, not by searxng-mcp itself — see above.

## Security Notes

Audited under `searxng-mcp-containerize-2026-08` (Phases 1-2: 0 Critical/High/Medium, 1 Info
accepted; Phase 3: 0 Critical/High, 1 Medium + 1 Low fixed, 5 Info). Two accepted deviations from
the standard network-isolation pattern, recorded in `accepted-risks.md`:

| ID | Status | Note |
|----|--------|------|
| NE-02 | Accepted | Joins the ~55-container `forge-net` rather than a purpose-built network pair — bearer auth is judged the actual control here |
| NE-03 | Accepted | In-container `0.0.0.0` bind — required for container-name DNS resolution; the startup guard makes an unauthenticated non-loopback bind loud rather than silent |

Migration is not yet fully complete — a couple of follow-up phases (cron reconciliation, cleanup)
remain tracked separately. Part of the cleanup landed on 2026-11-19, when the PM2-era launcher
scripts were deleted. The chat-UI integration piece of that follow-up has landed since this
was written: a chat UI now calls the reranker sidecar directly (see the reranker note above),
independent of searxng-mcp.

## Related Docs

- [project README](https://github.com/TadMSTR/searxng-mcp) — full tool reference, architecture,
  domain capability DB schema
- [project CHANGELOG](https://github.com/TadMSTR/searxng-mcp/blob/main/CHANGELOG.md) — per-release
  detail behind the 2026-11 summary above
- `services.md` (host-forge-knowledge-base) — port registry entry
- Phase docs (host-forge-knowledge-base): `phases/searxng-mcp-domain-db-writeloss-2026-08.md`,
  `phases/searxng-mcp-containerize-2026-08.md`
