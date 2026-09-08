# searxng-mcp

An MCP server for private web search via a self-hosted [SearXNG](https://github.com/searxng/searxng)
instance — search with local ML reranking, full-page fetch via a Firecrawl/Crawl4AI/raw-HTTP
cascade, and a domain capability database that learns which fetch tier works for which host. See
the [project README](https://github.com/TadMSTR/searxng-mcp) for the full tool/architecture
reference; this doc covers forge's deployment of it.

- **Version:** v3.29.0
- **Runs as:** Docker container in the `searxng` stack (`~/docker/searxng/docker-compose.yml`),
  co-located with SearXNG itself since a 2026-08-23 stack consolidation. As of the v3.26.0
  cutover the container runs a published, digest-pinned image
  (`ghcr.io/tadmstr/searxng-mcp:v3.29.0`) rather than a local build off repo main — a supply-chain
  improvement as much as a convenience: the image is now reproducible from a tagged release
  instead of whatever commit happened to be checked out at build time
- **Endpoint:** `http://127.0.0.1:8504` — bearer-authed
- **Transport:** streamable-http
- **Agents:** all agent manifests (developer, sysadmin, security, writer, research, harlock)

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
it no longer exists. There is one instance of this service now, not two.

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
surprises people, worth knowing before assuming a 503 means the process is down.

## Configuration

| Variable | Purpose |
|----------|---------|
| `SEARXNG_MCP_AUTH_TOKEN` | Bearer token clients must present; injected via manifest env from `SEARXNG_MCP_TOKEN` |
| `SEARXNG_MCP_TRANSPORT` / `SEARXNG_MCP_HOST` / `SEARXNG_MCP_PORT` | Fixed to `http` / `0.0.0.0` / `8504` in the container — the `8504:8504` host publish depends on the port override matching |
| `DOMAIN_DB_SNAPSHOT_DIR` / `DOMAIN_DB_SNAPSHOT_RETENTION` | Domain-capability-DB snapshot durability (`/snapshots`, retention 60) |
| Service URLs (`SEARXNG_URL`, `FIRECRAWL_URL`, `RERANKER_URL`, `CRAWL4AI_URL`, `OLLAMA_URL`, `KIWIX_URL`, `ADBLOCK_PROXY_URL`, `NATS_URL`) | See `docker-compose.yml` — several of these are easy to get wrong across the container/host boundary, see below |
| `NATS_USER` / `NATS_SUBJECT_PREFIX` | `searxng-mcp` / `events.searxng` |

Secrets: `/home/ted/.secrets/searxng-mcp.env`, chmod 600. Deliberately **not** `forge.env` — that
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
short version, it's isolated on a network with exactly one consumer.

The solver tier is deliberately a last resort, not a default: spinning up a full browser session
per request is far more expensive than any other tier, so it only runs when everything cheaper
has already failed.

## Hardening

- `user: 1000:1000`, `cap_drop: [ALL]`, `no-new-privileges:true`
- `read_only: true` root filesystem + tmpfs `/tmp` — all state lives in Valkey; the only writable
  path is the bind mount `/opt/appdata/searxng/domain-db-snapshots` → `/snapshots`. If something
  ever turns out to need a writable root, find out *what* before dropping this flag.
- `mem_limit: 2g`, `cpus: 2.0`, `ulimits: core: 0`
- Networks: `forge-net` and `fetch-net` — the latter carries no other traffic, it exists purely
  so searxng-mcp can reach `adblock-proxy` and Byparr without either being reachable from
  `forge-net`'s much larger population of containers

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

`pm2 start searxng-mcp` **no longer works on its own** — the PM2 entry was deleted, not just
stopped. Recreate it from `~/.claude/comms/artifacts/searxng-mcp-phase3/pm2-searxng-mcp.json`
(`bash /home/ted/scripts/run-searxng-mcp-http.sh`, fork mode, cwd `/home/ted`), then
`docker compose -f ~/docker/searxng/docker-compose.yml down`. The manifests' bearer header is
harmless against the PM2 instance — it has no auth check to reject it with.

## scoped-mcp Integration

All 6 agent manifests carry `Authorization: Bearer ${SEARXNG_MCP_TOKEN}`, resolved from
`/opt/appdata/agents/<type>/.env`. Tool scoping (e.g. `clear_cache` denylisting) is enforced at
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
remain tracked separately. The chat-UI integration piece of that follow-up has landed since this
was written: a chat UI now calls the reranker sidecar directly (see the reranker note above),
independent of searxng-mcp.

## Related Docs

- [project README](https://github.com/TadMSTR/searxng-mcp) — full tool reference, architecture,
  domain capability DB schema
- `services.md` (host-forge-knowledge-base) — port registry entry
- Phase docs (host-forge-knowledge-base): `phases/searxng-mcp-domain-db-writeloss-2026-08.md`,
  `phases/searxng-mcp-containerize-2026-08.md`
