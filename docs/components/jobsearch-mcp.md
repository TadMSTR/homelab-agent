# jobsearch-mcp

A self-hosted MCP server that turns a chat agent into a full job search assistant —
searching multiple job boards, building a resume profile, scoring fit against listings,
tailoring resumes, and tracking applications through a pipeline. Migrated from a
personal-workstation deployment to the shared platform.

- **Source:** `~/repos/personal/jobsearch-mcp` (`TadMSTR/jobsearch-mcp`, public)
- **Version:** v2.2.0
- **Stack dir:** `~/docker/jobsearch/` (build context points back at the repo checkout,
  same pattern as other forge stacks with a local build)

## Port / Endpoint

`127.0.0.1:8383` — streamable-http MCP endpoint (`/mcp`). Loopback-only: the server has
**no built-in authentication** of its own. It trusts a caller-supplied `X-User-ID` header
for all per-user data partitioning (profile, tracked jobs, notes), so every consumer must
sit behind something that sets that header after authenticating the user.

## Configuration

Key environment variables (full list in `.env.example` in the repo):

| Variable | Purpose |
|----------|---------|
| `ADZUNA_APP_ID` / `ADZUNA_APP_KEY` | Job search + salary data (only externally-configured job source) |
| `ANTHROPIC_API_KEY` | Fit scoring, profile parsing, resume tailoring (`claude-haiku-4-5`) |
| `POSTGRES_URL` / `QDRANT_URL` / `VALKEY_URL` | Internal datastore connections |
| `FIRECRAWL_URL` / `CRAWL4AI_URL` | Multi-tier job description extraction |
| `OLLAMA_HOST` / `OLLAMA_EMBED_MODEL` | Embeddings for semantic job matching (`bge-m3`) |
| `USAJOBS_API_KEY` / `FINDWORK_API_KEY` | **Never configured on this deployment — left empty deliberately.** These sources have never worked here; do not populate. |

Secrets are sourced from the platform secrets file, not committed to the stack compose.

## Dependencies

Five services defined in the compose file; four run by default.

| Container | Image | Runs by default? |
|-----------|-------|-------------------|
| `jobsearch-mcp` | local build | yes |
| `jobsearch-postgres` | `postgres:16` | yes |
| `jobsearch-qdrant` | `qdrant/qdrant:v1.18.3` | yes |
| `jobsearch-valkey` | `valkey/valkey:7-alpine` | yes |
| `job-watcher` | local build | **no** — gated behind compose profile `watcher`; needs SMTP and a per-user alert address, neither configured yet. Start with `docker compose --profile watcher up -d job-watcher` once those land. |

External dependencies: Anthropic API, Adzuna API, a self-hosted Firecrawl instance,
Crawl4AI, and Ollama (`bge-m3` embedding model).

### Network isolation

**Not on the platform-wide bridge network.** Because the MCP port carries no
authentication and `X-User-ID` is an unverified client assertion, a 2026-08 security
audit required narrowing this service off the shared network entirely — leaving it there
would have let every container on that network read or overwrite any user's profile and
job history. It now sits on three purpose-built networks instead:

- `jobsearch-deps` — outbound only, reaches Firecrawl / Crawl4AI / Ollama
- `librechat-jobsearch` — inbound only, from the chat app consumer (below)
- `jobsearch-net` — private, the three datastores

This cut reachable co-tenants from dozens down to 4. It's a mitigation, not a fix — the
durable fix is bearer auth on the MCP port itself, tracked upstream in the repo.

### Consumers

Two, both supplying `X-User-ID` themselves since the server does not authenticate:

1. **CloudCLI jobsearch agent** — via a per-agent scoped-mcp proxy on its own loopback
   port. Single-user (static `X-User-ID`), not part of the build/deploy agent fleet —
   personal-tool credentials only (no Vault approle, no task-queue/agent-bus/githost/Matrix
   modules).
2. **Chat app (LibreChat)** — reaches the server by container name over
   `librechat-jobsearch`, passing the logged-in user's ID as `X-User-ID` so multiple chat
   users share one deployment without seeing each other's data.

## Operations

```bash
# Health / reachability
curl -s http://127.0.0.1:8383/mcp -o /dev/null -w '%{http_code}\n'

# Container lifecycle
docker compose -f ~/docker/jobsearch/docker-compose.yml restart jobsearch-mcp
docker logs jobsearch-mcp --tail 50

# Rebuild after a repo update
docker compose -f ~/docker/jobsearch/docker-compose.yml build jobsearch-mcp
docker compose -f ~/docker/jobsearch/docker-compose.yml up -d jobsearch-mcp
```

Datastores (`jobsearch-postgres`, `jobsearch-qdrant`, `jobsearch-valkey`) run as root
inside their containers — an upstream constraint of the official images, not a hardening
gap here. They publish no host ports and sit on `jobsearch-net` only, reachable solely by
`jobsearch-mcp` and `job-watcher`. The two application containers (`jobsearch-mcp`,
`job-watcher`) run as UID 1000 with `cap_drop: ALL` and `no-new-privileges`.

## scoped-mcp Integration

Not proxied through the standard 6-agent scoped-mcp fleet. Accessed only via the
dedicated CloudCLI jobsearch agent's own scoped-mcp module and directly by the chat app —
see [Consumers](#consumers) above.

## Related Docs

- [librechat.md](apps/librechat.md) — the chat app consumer
