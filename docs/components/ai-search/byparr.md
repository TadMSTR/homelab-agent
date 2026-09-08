# Byparr

Byparr is a FlareSolverr-style headless-browser HTTP service: it solves JS- and Cloudflare-style
bot challenges and hands back cookies/HTML a caller can reuse for a plain HTTP fetch. It's the
challenge-solver tier for searxng-mcp's fetch cascade — when a target page returns a challenge
page instead of content, searxng-mcp hands the URL to Byparr instead of failing the fetch.

- **Compose:** `~/docker/searxng/docker-compose.yml` (same stack as searxng-mcp, adblock-proxy,
  and reranker)
- **Port:** none published to the host — reached only by its one consumer, over an internal
  network
- **Network:** a narrow service-to-service network shared only with searxng-mcp — deliberately
  not on the wider network the rest of the agent stack uses (see below)
- **No SWAG proxy** — never exposed outside the host
- **Auth:** none — the control here is network placement, not a token (see below)

## Role in the Fetch Cascade

See [searxng-mcp.md](searxng-mcp.md#solver-tier-byparr) for the full fetch-tier cascade and how
the solver tier gets invoked; this doc covers Byparr from its own side.

searxng-mcp's standard fetch tiers (Firecrawl, Crawl4AI, raw HTTP) assume a target page returns
content directly. Some sites don't — they interpose a JS-executing challenge page that a plain
HTTP client can't get past. Byparr runs a real headless browser, executes the challenge, and
returns the resulting cookies/HTML so the caller can retry the fetch. searxng-mcp only reaches
for Byparr when a standard fetch tier reports a block or challenge response — it's a fallback
tier for pages the other tiers can't reach, not a primary one, since spinning up a full browser
per request is far more expensive than a plain HTTP fetch.

## Network Placement — Why It's Isolated

Byparr has no authentication of its own, and its entire job is to fetch an arbitrary URL and
render it. If it were reachable from a broad, shared agent network, any caller on that network
could point it at an arbitrary address — including internal-only services — and get Byparr to
fetch it on their behalf. That's a textbook SSRF primitive: an unauthenticated service that
fetches whatever URL it's given is dangerous in proportion to how many things can reach it.

The mitigation isn't in Byparr — it's in placement. Byparr sits on a narrow, purpose-built
network with exactly one consumer (searxng-mcp) and nothing else, never on the shared network
the rest of the agent stack rides on. This is a general pattern worth applying to any
unauthenticated, arbitrary-URL-fetching service: give it the smallest network that still lets its
one legitimate caller reach it, not the same network everything else shares.

No host port is published, for the same reason — the only path in is through that narrow
internal network, from the one service that's supposed to use it.

## Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| `shm_size` | `1g` | Chromium (inside Byparr) needs real shared memory to render pages; too small and the browser process crashes mid-render |
| `mem_limit` | `2g` | Headless Chromium is memory-hungry; caps a single browser session from starving the host |
| `cap_drop` | `[ALL]` | Defense in depth — Byparr's whole job is rendering untrusted, potentially hostile pages |
| `no-new-privileges` | `true` | Same reasoning — no privilege-escalation path even if the browser sandbox is ever defeated |

No environment-based auth token is configured, and none is needed — see Network Placement above.

## Health Check

```
GET http://byparr:8191/health
```

Checked via `curl -f` as the container healthcheck. A failing check means the headless browser
process isn't responding — check container logs for a Chromium crash first (often traced to
`shm_size` being too small for the page in question, though it's set generously here already).

## Consumer

searxng-mcp is Byparr's only consumer. It reaches Byparr at a fixed internal address
(`SOLVER_URL=http://byparr:8191`) with `SOLVER_ENABLED=true`. See
[searxng-mcp.md](searxng-mcp.md#solver-tier-byparr) for when and how the solver tier actually
gets invoked in the fetch cascade.

## Operations

```bash
# Status
docker compose -f ~/docker/searxng/docker-compose.yml ps byparr

# Logs
docker compose -f ~/docker/searxng/docker-compose.yml logs -f byparr

# Manual health check — no published host port, so run it from inside the network
docker compose -f ~/docker/searxng/docker-compose.yml exec searxng-mcp curl -f http://byparr:8191/health
```

## Related Docs

- [searxng-mcp.md](searxng-mcp.md) — the caller; describes the full fetch-tier cascade and when
  the solver tier gets invoked
- [reranker.md](reranker.md) — another sidecar in the same search pipeline, isolated for a
  different reason (no auth of its own, mitigated by loopback-only publishing instead of network
  isolation, since it has a second consumer outside this stack)
