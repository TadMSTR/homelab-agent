# jobsearch-mcp

jobsearch-mcp turns a LibreChat agent into a full job search assistant — search across multiple boards, fetch and score listings against a resume, and track applications through a pipeline. It's a FastMCP server built specifically for multi-user LibreChat deployments, with all state partitioned per user so multiple household or team members can use the same instance independently.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) alongside the other LibreChat tooling. The MCP server exposes a `streamable-http` endpoint on port 8383; LibreChat agents reach it via `host.docker.internal`.

- **Source:** [TadMSTR/jobsearch-mcp](https://github.com/TadMSTR/jobsearch-mcp)
- **Transport:** streamable-http (port 8383)
- **Stack:** FastMCP · Postgres 16 · Qdrant · Valkey · Ollama (bge-m3) · Firecrawl / Crawl4AI

## Why jobsearch-mcp

Most job search tools in the AI space do one thing — search listings or generate cover letters. This one connects the full workflow in a single agent context:

1. Search across Adzuna, Remotive, WeWorkRemotely, Jobicy, USAJobs, and more
2. Fetch full job descriptions via a multi-tier enrichment pipeline (Firecrawl → Crawl4AI → rawFetch)
3. Build and store a structured resume profile — scoring and tailoring tools use it automatically
4. Score resume fit using Claude (structured breakdown: matched skills, gaps, seniority fit, ATS score, apply/maybe/skip)
5. Index listings for semantic matching — find jobs similar to a target role
6. Track applications through a pipeline with notes and status updates
7. Receive email alerts via `job-watcher` when new listings match your saved roles

The multi-user design means it works cleanly in a household or shared LibreChat instance. Each LibreChat user gets their own tracked pipeline. The MCP server identifies users via request headers injected by LibreChat.

## What's in the Stack

Five containers:

| Container | Image | Purpose |
|-----------|-------|---------|
| jobsearch-mcp | Local build | FastMCP server, port 8383 |
| job-watcher | Local build | Background poller — sends SMTP email alerts for new listings |
| jobsearch-postgres | postgres:16 | Per-user tracking state, application pipeline, notes, profiles |
| jobsearch-qdrant | qdrant/qdrant | Vector index for semantic job matching |
| jobsearch-valkey | valkey/valkey:7-alpine | Enrichment cache — avoids re-fetching recently seen JDs |

The MCP containers share an isolated `jobsearch-net` bridge network. Only the MCP server binds a host port (8383) — this is how LibreChat and other clients reach it via `host.docker.internal:8383`. If you need to attach the stack to an external Docker network (e.g., for a proxy or sidecar), use a `docker-compose.override.yml` rather than editing the base compose file.

## Prerequisites

Before deploying, you need:

| Service | Purpose | Notes |
|---------|---------|-------|
| **Adzuna** | Job search API, salary data | Free key at [developer.adzuna.com](https://developer.adzuna.com/) |
| **Anthropic** | Powers `score_fit`, `build_profile`, `tailor_resume` | Uses `claude-haiku-4-5` — inexpensive |
| **Ollama** | Embeddings for semantic job matching | Run locally; pull `bge-m3` before first `index_job` call |
| **Firecrawl** | Primary JD extraction | Use the self-hosted firecrawl-simple stack — no API key needed |
| **Crawl4AI** | Fallback JD extraction | Optional but recommended; self-hosted, no key needed |
| **SMTP relay** | job-watcher email alerts | Brevo free tier works (587/STARTTLS); only needed if using job-watcher |
| **USAJobs** | Government job listings | Optional API key + email at [developer.usajobs.gov](https://developer.usajobs.gov/); works without key at reduced rate limits |
| **Findwork** | Tech job board | Optional key at [findwork.dev](https://findwork.dev/); omit to skip source |

Postgres, Qdrant, and Valkey are included in the compose stack — no external services needed for those.

## Deployment

Clone the source repo (the compose file builds from source):

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

# Firecrawl (self-hosted firecrawl-simple)
FIRECRAWL_URL=http://host.docker.internal:3002

# Crawl4AI fallback (self-hosted, optional)
CRAWL4AI_URL=http://host.docker.internal:11235

# Ollama embeddings
OLLAMA_HOST=http://host.docker.internal:11434
OLLAMA_EMBED_MODEL=bge-m3

# Anthropic (for score_fit, build_profile, tailor_resume)
ANTHROPIC_API_KEY=YOUR_ANTHROPIC_API_KEY

# USAJobs (optional — omit for anonymous access with lower rate limits)
USAJOBS_API_KEY=YOUR_USAJOBS_API_KEY
USAJOBS_EMAIL=YOUR_EMAIL

# Findwork (optional — omit to skip source)
FINDWORK_API_KEY=YOUR_FINDWORK_API_KEY
```

Create `job-watcher.env` for the alert service:

```bash
# Postgres (same as above)
POSTGRES_URL=postgresql://jobsearch:YOUR_STRONG_PASSWORD@jobsearch-postgres:5432/jobsearch

# SMTP relay
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=YOUR_SMTP_USER
SMTP_PASSWORD=YOUR_SMTP_PASSWORD
SMTP_FROM=alerts@example.com

# Adzuna + USAJobs (for watcher searches)
ADZUNA_APP_ID=YOUR_ADZUNA_APP_ID
ADZUNA_APP_KEY=YOUR_ADZUNA_APP_KEY
USAJOBS_API_KEY=YOUR_USAJOBS_API_KEY
USAJOBS_EMAIL=YOUR_EMAIL

# How often to poll (seconds, default 4h)
JOB_WATCH_INTERVAL_SECONDS=14400
```

Update `docker-compose.yml` to point `build.context` at your cloned repo path, then build and start:

```bash
docker compose build
docker compose up -d
```

The Postgres schema and Qdrant collection are created automatically on first startup.

**If upgrading from v1:** The Qdrant `jobs` collection must be dropped and recreated — the embedding space changed from Voyage AI to Ollama bge-m3:

```bash
docker exec jobsearch-qdrant curl -X DELETE http://localhost:6333/collections/jobs
```

The collection will be recreated automatically on the next `index_job` call.

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

The server exposes tools across five categories. An agent can use any subset — you don't need to run the full workflow:

**Resume profile:** `build_profile` (parse raw resume/bio text into a structured profile via Claude — returns for review, does not auto-save), `save_profile` (store the structured profile — scoring and tailoring tools use it automatically), `get_profile` (retrieve stored profile), `delete_profile` (remove stored profile and associated data), `tailor_resume` (rewrite your stored profile's highlights and summary to match a specific JD — returns tailored version, does not overwrite stored profile)

**Search and discovery:** `search_jobs` (multi-board search), `get_job_detail` (full JD via enrichment pipeline), `check_active` (is listing still live?), `salary_insights` (salary distribution for a role)

**Semantic matching:** `index_job` (store a listing in Qdrant using Ollama bge-m3 embeddings), `match_jobs` (find listings similar to a resume or target role)

**Fit scoring:** `score_fit` (Claude-powered resume/JD analysis returning matched skills, gaps, seniority fit, ATS score, and apply/maybe/skip — uses stored profile if no resume passed), `cover_letter_brief` (structured writing guide, not a finished letter — uses stored profile if no resume passed)

**Application tracking:** `mark_applied`, `mark_seen`, `update_status` (seen → applied → interviewing → offered → rejected), `add_note`, `get_my_jobs`

## Job Watcher

The `job-watcher` container runs independently from the MCP server. It polls Adzuna, Remotive, WeWorkRemotely, and USAJobs on a configurable interval, matches results against each user's stored profile (specifically the `target_roles` and `skills` fields from `build_profile`), and sends an SMTP email listing new matches.

It only alerts on listings it hasn't seen before — deduplication is handled via Valkey. Email goes to the address stored in the user's profile (`email` field). No MCP tool interaction needed — it runs purely in the background.

To disable job-watcher without removing it, set `JOB_WATCH_INTERVAL_SECONDS` to a very large value or remove the service from the compose file.

## Gotchas and Lessons Learned

**Embedding space changed in v2.** Voyage AI was replaced with Ollama bge-m3. Any Qdrant index built with v1 is incompatible — the collection must be dropped before upgrading. See the upgrade note in the Deployment section.

**Multi-tier enrichment.** `get_job_detail` and all tools that fetch a JD internally use a three-tier fallback: Firecrawl → Crawl4AI → rawFetch. If Firecrawl is down or rate-limited, the next tier kicks in automatically. Results are cached in Valkey (key: `job:enrich:<url>`) — subsequent calls for the same URL return the cached version instantly.

**LinkedIn scraping is fragile.** LinkedIn results use Playwright and depend on their current page structure. Expect occasional failures. The API-based sources (Adzuna, RSS boards, USAJobs) are stable.

**Indeed/Glassdoor/ZipRecruiter are opt-in.** These scraping-based sources via python-jobspy are not included in the default `search_jobs` call — pass them explicitly in the `sources` parameter. They're rate-limited aggressively; the server applies exponential backoff (60s → 15min) per site when they error.

**USAJobs is a default source.** Unlike v1, `usajobs` is included in the default sources list for `search_jobs`. Findwork and The Muse are optional — pass explicitly in `sources` for tech-focused or culture-focused results respectively.

**`score_fit` uses stored profile automatically.** If you've called `save_profile`, you can call `score_fit` with just a URL — no need to paste resume text each time. Explicit `resume` argument takes priority if passed.

**`score_fit` truncates content.** JDs are truncated to 6000 chars, resumes to 3000 chars before passing to Claude. Very long job descriptions lose their tail — typically fine, but worth knowing if scoring seems off on verbose postings.

**Qdrant collection is auto-created.** The `jobs` collection is created on first `index_job` call (or recreated after a drop). No manual Qdrant setup needed.

**`bge-m3` must be pulled before first use.** On a fresh Ollama instance, `index_job` will fail until the model is available:

```bash
curl http://localhost:11434/api/pull -d '{"name": "bge-m3"}'
```

**CVE-2025-46656 is a known suppressed finding in CI.** The vuln is in `markdownify` (a transitive dep of `python-jobspy`) and cannot be fixed locally — it requires an upstream release. CI runs `pip-audit --ignore-vuln CVE-2025-46656` to keep the gate passing. The suppression is intentional and documented in `ci.yml`. Accept it as an upstream-blocked risk until a fix ships.

## CI

GitHub Actions workflows added in v2.1.0:

| Workflow | Triggers | What it does |
|----------|----------|--------------|
| `ci.yml` | Push, PR to `main` | Runs tests on Python 3.11, 3.12, 3.13; ruff lint+format check; `pip-audit` dependency scan |
| `release.yml` | Push of `v*` tag | Builds wheel + sdist, creates a GitHub Release with attached artifacts |

Both workflows use SHA-pinned actions. The `pip-audit` step runs with `--ignore-vuln CVE-2025-46656` (see Gotcha above).

## Standalone Value

High, if you're actively job searching. The v2 profile system in particular changes the workflow: build your profile once with `build_profile`, store it with `save_profile`, and every subsequent `score_fit`, `cover_letter_brief`, and `tailor_resume` call works without pasting resume text again.

The stack is niche (not everyone is job hunting), but it's also a good reference implementation of a non-trivial FastMCP server: Postgres persistence, vector search via Qdrant, Valkey caching, multi-tier enrichment with fallback, multi-user partitioning via request headers, and Claude integration for structured output.

## Related Docs

- [LibreChat](librechat.md) — MCP integration pattern and `host.docker.internal` setup
- [MCP servers reference](../../mcp-servers/README.md) — jobsearch-mcp entry with config pattern
- [Docker compose](../../docker/jobsearch/) — five-container stack definition
- [Source repo](https://github.com/TadMSTR/jobsearch-mcp) — full source, Dockerfile, `.env.example`
