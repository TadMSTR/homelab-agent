# Hister

Hister is a self-hosted semantic and keyword search engine over the Claude memory corpus. It provides browser-based search independent of any live Claude session — useful for reviewing past decisions, finding prior research, or locating build context without opening Claude Code. The web UI runs behind Authelia SSO; an MCP endpoint at `/mcp` provides programmatic access.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, alongside the Docker service stack, but it serves [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) agents as a memory access path.

## Why Hister

memsearch and qmd both provide memory search, but they require an active Claude Code session to invoke. Hister fills the gap: a persistent web UI that lets you search the memory corpus from any browser, at any time, without starting an agent.

It also fills a different niche than memsearch (automatic, session-scoped recall) and qmd (on-demand search over repos and docs). Hister is the read-only window into the memory corpus for humans — a way to browse and verify what the agents actually know, especially useful after a memory-sync or memory-flush run.

## Architecture

Hister runs as a two-container Docker stack on `claudebox-net`. The main container handles search; a companion container handles markdown preview rendering.

```
Browser / MCP client
        │
        ▼
   SWAG (reverse proxy — hister.yourdomain)
        │
        ├── /              ──→ hister container (4433)       — Authelia SSO required
        ├── /search        ──→ hister container (4433)       — no Authelia (WebSocket)
        ├── /api/preview   ──→ hister-preview container (4434) — no Authelia
        ├── /api/*         ──→ hister container (4433)       — no Authelia
        └── /mcp           ──→ hister container (4433)       — no Authelia
```

**Search stack:**
- **Semantic search** — `nomic-embed-text` embeddings via Ollama on the forge GPU
- **Keyword search** — Bleve full-text index (built into the Hister binary)
- **SearXNG fallback** — fires on zero results, broadens coverage to web sources

**Corpus (~500 files, read-only volume mounts):**

| Mount | Source |
|-------|--------|
| `/mnt/memory-shared` | `~/.claude/memory/shared/` |
| `/mnt/memory-agents` | `~/.claude/memory/agents/` |
| `/mnt/prime-directive` | `~/repos/personal/claude-prime-directive/` |
| `/mnt/build-plans` | `~/.claude/comms/artifacts/build-plans/` |
| `/mnt/helm-platform` | `~/repos/personal/helm-platform/` |
| `/mnt/blog` | `~/repos/personal/blog/` |

Phase 4 (docs cache mount, ~2483 additional files from `~/.claude/memory/docs/`) is deferred — see [Deferred Work](#deferred-work) below.

## Preview Container

The Hister container's built-in markdown preview requires `chromedp` (headless Chrome), which is not available in the container image. A companion `hister-preview` container intercepts `/api/preview` requests via SWAG and renders markdown as styled HTML without Chrome.

The `hister-preview` container is defined in the same `docker-compose.yml` as the main `hister` service, using a local build context (`./preview/`). The preview script (`~/scripts/hister-preview.py`) is mounted read-only into the container at `/app/hister-preview.py`.

**How it works:**
1. SWAG routes `/api/preview` to `hister-preview` (port 4434) before the request reaches the Hister container
2. The container fetches the raw file via Hister's `/api/file` endpoint
3. Strips YAML frontmatter, converts with the Python `markdown` library
4. Returns JSON matching Hister's preview response schema: `{title, content, html, htmlType}`

The preview script is tracked in the `claudebox-scripts` git repo, not in homelab-agent.

## Auth and Access

| Path | Auth | Reason for bypass |
|------|------|-------------------|
| `/` (web UI) | Authelia SSO | — |
| `/search` | None | WebSocket upgrade is blocked by `auth_request` |
| `/api/preview` | None | Routed to preview container; SPA sub-request |
| `/api/*` | None | SPA sub-requests; accepted LAN-only risk |
| `/mcp` | None | MCP clients don't have SSO session cookies |

No access token is configured — the stack is internal-only (your private domain, not internet-facing) and the web UI is gated by Authelia. The `/api` and `/mcp` bypass is an accepted LAN risk: any host on `claudebox-net` can reach these endpoints without credentials.

## Configuration

Compose file: `~/docker/hister/docker-compose.yml`  
Hister config: `~/docker/hister/data/config.yml` (corpus paths, Ollama endpoint, SearXNG URL)  
SWAG proxy conf: `/opt/appdata/swag/nginx/proxy-confs/hister.subdomain.conf`

The compose stack (`~/docker/hister/`) is covered by `docker-stack-backup` (nightly, 1 AM). The preview script (`~/scripts/hister-preview.py`) is covered by the `~/scripts/` rsync in backup.

The deploy script (`claudebox-deploy.sh`) includes the Hister stack in bring-up.

## Deferred Work

Two phases were scoped but not implemented in the initial deployment:

**Phase 3 — MCP integration to Claude Code:** Wire the Hister MCP endpoint into `~/.claude/settings.json` as a configured MCP server so agents can query it via tool calls during sessions. Currently agents use memsearch and qmd for in-session memory search; Hister's MCP endpoint exists but is not registered in the Claude Code config.

**Phase 4 — Docs cache mount:** Mount `~/.claude/memory/docs/` into the Hister corpus. This adds ~2483 files (pre-fetched official service docs) to the searchable corpus. Skipped in Phase 1 to keep initial scope manageable.

## Security Note

> **SSRF risk under review.** The preview container fetches file content by calling Hister's `/api/file` endpoint with a path from the incoming request. The container does not currently validate that the requested path is within the configured corpus root. A security audit is pending — do not expose the preview or `/api/*` routes to untrusted networks until the audit is complete and mitigations are applied.

## Gotchas

**Stale PM2 entry.** A `hister-preview` PM2 entry (id 27) exists in stopped/disabled state — a leftover from the development phase before the preview shim was moved into Docker. It is not active and should be ignored. The Docker container (`hister-preview` service) is the running instance.

**`/search` bypasses Authelia.** This is required — the Nginx `auth_request` directive blocks WebSocket upgrades, so adding Authelia to `/search` breaks real-time search results. The tradeoff is that anyone who can reach the subdomain can run searches without logging in. Acceptable on a LAN-only domain; revisit if ever externally exposed.

**Semantic search depends on forge Ollama availability.** If the forge GPU host is unreachable, semantic search fails silently and only keyword search (Bleve) and the SearXNG fallback work. Check Hister's container logs if results seem unusually sparse.

**Corpus changes require container restart.** Adding new volume mounts to `docker-compose.yml` and updating `data/config.yml` with the new path requires `docker compose up -d` to take effect. The Bleve keyword index is rebuilt on startup; semantic embeddings are generated incrementally.

**Preview script changes need container restart.** The preview script is mounted read-only into the container. Edits to `~/scripts/hister-preview.py` take effect on container restart — not live.

## Related Docs

- [memsearch](memsearch.md) — automatic in-session memory recall (session-scoped, Claude Code plugin)
- [qmd](qmd.md) — on-demand semantic search over repos, docs, and agent memory
- [doc-sync](doc-sync.md) — local docs cache (feeds Phase 4 corpus expansion)
- [Architecture overview](../../README.md#layer-2--self-hosted-service-stack) — Layer 2 service stack context
