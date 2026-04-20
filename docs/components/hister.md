# Hister

Hister is a self-hosted semantic and keyword search engine over the Claude memory corpus. It provides browser-based search independent of any live Claude session — useful for reviewing past decisions, finding prior research, or locating build context without opening Claude Code. The web UI runs behind Authelia SSO; an MCP endpoint at `/mcp` provides programmatic access.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, alongside the Docker service stack, but it serves [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) agents as a memory access path.

## Why Hister

memsearch and qmd both provide memory search, but they require an active Claude Code session to invoke. Hister fills the gap: a persistent web UI that lets you search ~500 memory corpus files from any browser, at any time, without starting an agent.

It also fills a different niche than memsearch (automatic, session-scoped recall) and qmd (on-demand search over repos and docs). Hister is the read-only window into the memory corpus for humans — a way to browse and verify what the agents actually know, especially useful after a memory-sync or memory-flush run.

## Architecture

Hister runs as a single Docker container on `claudebox-net`, port 4433 (internal only).

```
Browser / Claude Code
        │
        ▼
   SWAG (reverse proxy)
        │
        ├── /              ──→ Hister container (port 4433) — Authelia SSO required
        ├── /api/preview   ──→ Preview shim (PM2, port 4434) — intercepts before Hister
        ├── /api/*         ──→ Hister container — Authelia bypassed
        └── /mcp           ──→ Hister container — Authelia bypassed
```

**Search stack:**
- **Semantic search** — `nomic-embed-text` embeddings via Ollama on the forge GPU
- **Keyword search** — Bleve full-text index (built into the Hister binary)
- **SearXNG fallback** — fires on zero results, broadens coverage to web sources

**Corpus (~500 files):**
- `~/.claude/memory/` — agent working memory (shared + per-agent)
- `~/repos/personal/claude-prime-directive/` — prime directive and project instructions
- `~/.claude/comms/artifacts/build-plans/` — build plans
- `~/repos/personal/homelab-agent/docs/` — platform documentation

Phase 4 (docs cache mount, ~2483 additional files from `~/.claude/memory/docs/`) is deferred — see [Deferred Work](#deferred-work) below.

## Preview Shim

The Hister container's built-in markdown preview requires `chromedp` (headless Chrome), which is not available in the container image. A Python HTTP shim (`~/scripts/hister-preview.py`) intercepts `/api/preview` requests via SWAG and renders markdown as styled HTML without Chrome.

**How it works:**
1. SWAG routes `/api/preview` to the shim (port 4434) before the request reaches the Hister container
2. The shim fetches the raw file via Hister's `/api/file` endpoint
3. Strips YAML frontmatter, converts with the Python `markdown` library
4. Returns JSON matching Hister's preview response schema: `{title, content, html, htmlType}`

The shim runs as a PM2 service (`hister-preview`, always-on, port 4434). It is tracked in the `claudebox-scripts` git repo, not in homelab-agent.

## Auth and Access

| Path | Auth | Notes |
|------|------|-------|
| `/` (web UI) | Authelia SSO | Standard SSO login — same session as other claudebox services |
| `/api/*` | None | Bypasses Authelia — raw file fetch, search API |
| `/mcp` | None | Bypasses Authelia — MCP endpoint for programmatic access |

The Hister access token is enforced via `data/config.yml` inside the container, not via the compose `environment:` block. The compose env token was removed after it caused a SPA reload loop. The `data/config.yml` file is the authoritative access control config for Hister.

The `/api` and `/mcp` bypass is intentional: agents querying the MCP endpoint don't have SSO session cookies. If you are concerned about unauthenticated access to the raw file API, add an IP allowlist or API token at the SWAG level.

## Configuration

Compose file: `~/docker/hister/docker-compose.yml`
Config file: `/opt/appdata/hister/data/config.yml` (access token, corpus path config)

Both the compose file and `data/config.yml` are covered by `docker-stack-backup` (nightly, 1 AM).

The deploy script (`claudebox-deploy.sh`) includes Hister in the stack bring-up sequence.

## Deferred Work

Two phases were scoped but not implemented in the initial deployment:

**Phase 3 — MCP integration to Claude Code:** Wire the Hister MCP endpoint into `~/.claude/settings.json` as a configured MCP server so agents can query it via tool calls during sessions. Currently agents use memsearch and qmd for in-session memory search; Hister's MCP endpoint exists but is not registered in the Claude Code config.

**Phase 4 — Docs cache mount:** Mount `~/.claude/memory/docs/` into the Hister corpus. This adds ~2483 files (pre-fetched official service docs) to the searchable corpus. Skipped in Phase 1 to keep initial scope manageable. The volume mount is straightforward once the other phases are validated.

## Security Note

> **SSRF risk under review.** The preview shim fetches file content by calling Hister's `/api/file` endpoint with a path from the incoming request. The shim does not currently validate that the requested path is within the configured corpus root. A security audit is pending — do not expose the preview shim or `/api/*` routes to untrusted networks until the audit is complete and any SSRF mitigations are applied.

## Gotchas

**Access token in `data/config.yml`, not compose env.** Setting `HISTER_ACCESS_TOKEN` in the compose `environment:` block causes a SPA reload loop (the token is picked up by the frontend, which re-validates on every route change). The correct location is `data/config.yml` inside the container. The compose env entry was removed — don't re-add it.

**Semantic search depends on forge Ollama availability.** If the forge GPU host is unreachable, semantic search fails silently and only keyword search (Bleve) works. The SearXNG fallback fires on zero results regardless. Check Hister's container logs if search results seem unusually sparse.

**Corpus changes require reindex.** Adding new directories to the corpus config requires a container restart for Hister to pick them up and rebuild its index. The Bleve keyword index is rebuilt on startup; semantic embeddings are generated incrementally.

**Preview shim covers only markdown files.** Files that aren't markdown (JSON, YAML, shell scripts) are returned as plain text without HTML conversion. The shim checks the file extension before invoking the markdown library.

## Related Docs

- [memsearch](memsearch.md) — automatic in-session memory recall (session-scoped, Claude Code plugin)
- [qmd](qmd.md) — on-demand semantic search over repos, docs, and agent memory
- [doc-sync](doc-sync.md) — local docs cache (feeds Phase 4 corpus expansion)
- [Architecture overview](../../README.md#layer-2--self-hosted-service-stack) — Layer 2 service stack context
