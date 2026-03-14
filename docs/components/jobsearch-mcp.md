# jobsearch-mcp

jobsearch-mcp turns a LibreChat agent into a full job search assistant — search across multiple boards, fetch and score listings against a resume, and track applications through a pipeline. It's a FastMCP server built specifically for multi-user LibreChat deployments, with all state partitioned per user so multiple household or team members can use the same instance independently.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) alongside the other LibreChat tooling. The MCP server exposes a `streamable-http` endpoint on port 8383; LibreChat agents reach it via `host.docker.internal`.

- **Source:** [TadMSTR/jobsearch-mcp](https://github.com/TadMSTR/jobsearch-mcp)
- **Transport:** streamable-http (port 8383)
- **Stack:** FastMCP · Postgres 16 · Qdrant · Voyage AI · Firecrawl

## Why jobsearch-mcp

Most job search tools in the AI space do one thing — search listings or generate cover letters. This one connects the full workflow in a single agent context:

1. Search across Adzuna, Remotive, WeWorkRemotely, Jobicy, and LinkedIn
2. Fetch full job descriptions via Firecrawl
3. Score resume fit using Claude (structured breakdown: matched skills, gaps, seniority fit, apply/maybe/skip)
4. Index listings for semantic matching — find jobs similar to a target role
5. Track applications through a pipeline with notes and status updates

The multi-user design means it works cleanly in a household or shared LibreChat instance. Each LibreChat user gets their own tracked pipeline. The MCP server identifies users via request headers injected by LibreChat.

## What's in the Stack

Three containers:

| Container | Image | Purpose |
|-----------|-------|---------|
| jobsearch-mcp | Local build | FastMCP server, port 8383 |
| jobsearch-postgres | postgres:16 | Per-user tracking state, application pipeline, notes |
| jobsearch-qdrant | qdrant/qdrant | Vector index for semantic job matching |

The three containers share an isolated `jobsearch-net` bridge network. Only the MCP server binds a host port (8383).

## Prerequisites

Before deploying, you need accounts and API keys for:

| Service | Purpose | Notes |
|---------|---------|-------|
| **Adzuna** | Job search API, salary data | Free key at [developer.adzuna.com](https://developer.adzuna.com/) |
| **Voyage AI** | Embeddings for semantic job matching | Free tier available at [dash.voyageai.com](https://dash.voyageai.com/) |
| **Anthropic** | Powers `score_fit` resume analysis | Uses `claude-haiku-4-5` — inexpensive |
| **Firecrawl** | Full job description extraction | Use the self-hosted firecrawl-simple stack already in the repo — no API key needed |

Postgres and Qdrant are included in the compose stack — no external services needed for those.

## Deployment

Clone the source repo (the compose file in this repo builds from source):

```bash
git clone https://github.com/TadMSTR/jobsearch-mcp.git /path/to/jobsearch-mcp
```

Create the `.env` file:

```bash
# Postgres credentials
POSTGRES_USER=jobsearch
POSTGRES_PASSWORD=YOUR_STRONG_PASSWORD

# Adzuna API
ADZUNA_APP_ID=YOUR_ADZUNA_APP_ID
ADZUNA_APP_KEY=YOUR_ADZUNA_APP_KEY

# Firecrawl Simple (self-hosted)
FIRECRAWL_URL=http://host.docker.internal:3002

# Voyage AI embeddings
VOYAGE_API_KEY=YOUR_VOYAGE_API_KEY

# Anthropic (for score_fit)
ANTHROPIC_API_KEY=YOUR_ANTHROPIC_API_KEY
```

Update `docker/jobsearch/docker-compose.yml` to point `build.context` at your cloned repo path, then build and start:

```bash
docker compose -f docker/jobsearch/docker-compose.yml build
docker compose -f docker/jobsearch/docker-compose.yml up -d
```

The Postgres schema and Qdrant collection are created automatically on first startup. No manual migration needed.

## LibreChat Integration

Add to `librechat.yaml` under `mcpServers`:

```yaml
mcpServers:
  jobsearch:
    type: streamable-http
    url: http://host.docker.internal:8383/mcp
    headers:
      X-User-ID: "{{LIBRECHAT_USER_ID}}"
      X-User-Email: "{{LIBRECHAT_USER_EMAIL}}"
      X-User-Username: "{{LIBRECHAT_USER_USERNAME}}"
```

The `X-User-ID` header is how the server partitions state per user. LibreChat injects the current user's identity into these headers automatically. Without it, all users would share a single pipeline.

The `host.docker.internal` hostname works because the LibreChat compose file already includes `extra_hosts: - "host.docker.internal:host-gateway"`. The jobsearch-mcp container binds `8383` to the host, so LibreChat containers can reach it at that address.

Restart LibreChat after editing `librechat.yaml`:

```bash
docker compose -f docker/librechat/docker-compose.yml restart librechat
```

## Tools

The server exposes tools across four categories. An agent can use any subset — you don't need to run the full workflow:

**Search and discovery:** `search_jobs` (multi-board search), `get_job_detail` (full JD via Firecrawl), `check_active` (is listing still live?), `salary_insights` (salary distribution for a role)

**Semantic matching:** `index_job` (store a listing in Qdrant), `match_jobs` (find listings similar to a resume or target role)

**Fit scoring:** `score_fit` (Claude-powered resume/JD analysis returning matched skills, gaps, seniority fit, score, and apply/maybe/skip), `cover_letter_brief` (structured writing guide, not a finished letter)

**Application tracking:** `mark_applied`, `update_status` (seen → applied → interviewing → offered → rejected), `add_note`, `get_my_jobs`

## Gotchas and Lessons Learned

**LinkedIn scraping is fragile.** LinkedIn results use Playwright and depend on their current page structure. Expect occasional failures. The API-based sources (Adzuna, RSS boards) are stable.

**Indeed/Glassdoor/ZipRecruiter are opt-in.** These scraping-based sources via python-jobspy are not included in the default `search_jobs` call — pass them explicitly in the `sources` parameter. They're rate-limited aggressively; the server applies exponential backoff (60s → 15min) per site when they error.

**Firecrawl URL in the container.** The `FIRECRAWL_URL` in the compose env should be `http://firecrawl-api:3002` if firecrawl-simple is on the same Docker network, or `http://host.docker.internal:3002` if it's on a different network. Since jobsearch-mcp uses its own isolated `jobsearch-net`, `host.docker.internal` is the path to the firecrawl stack.

**`score_fit` truncates content.** JDs are truncated to 6000 chars, resumes to 3000 chars before passing to Claude. Very long job descriptions lose their tail — typically fine, but worth knowing if scoring seems off on verbose postings.

**Qdrant collection is auto-created.** The `jobs` collection is created on first `index_job` call. No manual Qdrant setup needed.

## Standalone Value

High, if you're actively job searching. Combining multi-board search, full JD extraction, structured resume scoring, and an application tracker in a single agent tool is genuinely useful. The `score_fit` output in particular — a structured breakdown of exactly which skills match, which are missing, and a clear apply/maybe/skip recommendation — is more actionable than a generic cover letter generator.

The stack is niche (not everyone is job hunting), but it's also a good reference implementation of a non-trivial FastMCP server: Postgres persistence, vector search via Qdrant, multi-user partitioning via request headers, and Claude integration for structured output.

## Related Docs

- [LibreChat](librechat.md) — MCP integration pattern and `host.docker.internal` setup
- [MCP servers reference](../../mcp-servers/README.md) — jobsearch-mcp entry with config pattern
- [Docker compose](../../docker/jobsearch/) — three-container stack definition
- [Source repo](https://github.com/TadMSTR/jobsearch-mcp) — full source, Dockerfile, `.env.example`
