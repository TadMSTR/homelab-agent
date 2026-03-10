# Architecture Decisions

This document captures the major architectural choices behind the homelab-agent stack and the reasoning that drove them. Individual component docs cover implementation details — this is the consolidated "why" reference.

The decisions are roughly chronological. Earlier ones shaped the constraints that later ones operate within.

## Agent Memory: memsearch over Memory MCP

**Choice:** [memsearch](https://github.com/anthropics/memsearch) with local sentence-transformers embeddings.
**Alternatives considered:** Memory MCP (Anthropic's built-in), custom SQLite store.

Memory MCP stored data in an opaque JSON database with no agent scoping — every session saw everything. memsearch uses plain markdown files organized into per-agent and shared directories, generates embeddings locally (no API calls), and auto-injects relevant context via Claude Code plugin hooks. The markdown-first approach means memory files are human-readable, git-trackable, and indexable by other tools (qmd indexes the same files).

The directory structure (`~/.claude/memory/shared/`, `~/.claude/memory/agents/<name>/`) gives each agent its own memory scope while allowing cross-agent knowledge sharing through the shared directory. Memory MCP had no equivalent — it was a flat namespace. Memory MCP has since been removed from the stack.

## Document Search: qmd

**Choice:** [qmd](https://github.com/tobi/qmd) — hybrid BM25 + vector search with LLM reranking, served via MCP.
**Alternatives considered:** Vanilla RAG (ChromaDB + embeddings), grep/ripgrep, dedicated search services.

qmd indexes multiple collections (infrastructure docs, agent memory, compose files, deploy scripts) and serves them through a single interface. It supports both stdio transport (for Claude Desktop) and HTTP transport (for LibreChat and other services). The hybrid search approach — keyword matching via BM25, semantic matching via vector embeddings, then LLM reranking of combined results — outperforms pure vector search on technical documentation where exact terms matter.

GPU acceleration via Vulkan on the host's iGPU dropped embedding time from 3+ minutes to under a minute for the full collection. Worth enabling if your hardware supports it.

**Known limitation:** `query` and `vsearch` MCP tools crash the transport ([tobi/qmd#140](https://github.com/tobi/qmd/issues/140)). Workaround: restrict MCP-exposed tools to `search`, `get`, `multi_get`, `status`; use `qmd query` via CLI when hybrid search with reranking is needed.

## Chat Interface: LibreChat

**Choice:** [LibreChat](https://www.librechat.ai/) as the primary web-based chat UI.
**Alternatives considered:** Open WebUI, LobeChat, direct API access only.

LibreChat supports multiple AI providers (not locked to one), has native MCP tool integration, built-in agent creation with per-agent tool access, conversation memory that persists across sessions, and a web search pipeline with RAG. It's the primary interface for interactive agent work that doesn't need the full Claude Desktop environment — accessible from any device on the network.

Open WebUI is excellent for Ollama-first setups but its external API provider support felt like an afterthought. LobeChat looked polished but was thinner on agent tooling. LibreChat hit the right balance of features and active development.

## Reverse Proxy: Per-Host SWAG Instances

**Choice:** Each host runs its own [SWAG](https://github.com/linuxserver/docker-swag) instance with its own domain.
**Alternatives considered:** Single SWAG instance proxying all hosts, Traefik, Caddy.

Self-contained SWAG per host means each host manages its own SSL certs and proxy configs independently. No cross-host dependency — if one host goes down, the others keep serving. SWAG has first-class support for linuxserver.io containers (preset proxy confs), Authelia integration (uncomment two lines per proxy conf), and `SWAG_AUTORELOAD` picks up config changes without restarts. Cloudflare DNS validation for Let's Encrypt means no ports need to be exposed to the internet.

## SSO Authentication: Authelia

**Choice:** [Authelia](https://www.authelia.com/) (v4.38) for single sign-on across all web services.
**Alternatives considered:** Authentik, VoidAuth, per-service authentication.

SWAG ships with preset Authelia conf files (`authelia-server.conf`, `authelia-location.conf`) that make integration trivial — uncomment two includes per proxy conf. Authelia's file-based user backend (a YAML file with bcrypt-hashed passwords) is sufficient for a single-user or small household setup. No LDAP, no database, minimal resource usage. It's lighter than Authentik and more mature than VoidAuth.

Pinned to v4.38 because SWAG's built-in conf files target this version. Check for breaking changes before upgrading.

## Docker Backup: Stop-Before-Copy with docker-stack-backup

**Choice:** Custom backup script that stops containers before archiving appdata.
**Alternatives considered:** Live copy with rsync, Docker volume snapshots, filesystem-level snapshots.

MongoDB (used by LibreChat) and other stateful services can produce corrupt data files if copied while running. The docker-stack-backup approach eliminates this risk by doing a clean shutdown before archiving. The downtime window is typically under 2 minutes per stack at 1:00 AM — acceptable for a homelab. The script only restarts containers that were running before the backup, preventing accidentally starting services that were intentionally stopped.

Docker appdata lives at `/opt/appdata/` — separate from compose files at `~/docker/` and explicitly excluded from the Backrest/restic home directory backup. This separation keeps the backup scopes clean and avoids Backrest trying to snapshot live database files.

## Dual-Source Memory Sync

**Choice:** Memory-sync agent pulls from both Claude Code (memsearch markdown files) and LibreChat (MongoDB memory export).
**Alternatives considered:** Claude Code memory only, manual curation.

Different interaction modes produce different knowledge. A Claude Code CLI session debugging a Docker networking issue generates different insights than a LibreChat conversation exploring architecture options. Both are valuable. The memory-sync agent reads from both sources and writes distilled notes to separate output directories (`memory/distilled/claude-code/` and `memory/distilled/librechat/`) so provenance stays clear.

The 10-note-per-run cap prevents flooding the context repo after a week of heavy agent usage. If there's more durable knowledge than 10 entries, it catches the remainder on the next daily run.

## Process Management: PM2

**Choice:** [PM2](https://pm2.keymetrics.io/) for all non-Docker services and cron jobs.
**Alternatives considered:** systemd units, cron, supervisor.

PM2 handles always-on services (qmd HTTP, CUI) and scheduled jobs (memory-sync, qmd reindex, resource monitoring, dependency checks) through a single interface. It has built-in cron support, log management, startup hook generation for systemd, and `pm2 save`/`pm2 resurrect` for persisting the process list across reboots. The ecosystem config file serves as a single source of truth for all managed processes.

systemd would work for the always-on services but is more awkward for scheduled jobs (you'd need separate timer units). Raw cron works for schedules but doesn't give you process monitoring, log management, or restart policies. PM2 covers both patterns cleanly.

## Version Pinning Strategy

**Choice:** Pin single-maintainer and fast-moving dependencies; use `latest` cautiously.
**Specifics:**

| Dependency | Pinning | Rationale |
|------------|---------|-----------|
| memsearch | pip version pin | Single maintainer, small user base, breaking changes possible |
| qmd | Record installed version | Single maintainer, actively developed |
| Authelia | Docker tag pin (4.38) | SWAG conf compatibility |
| CUI | npm version or release tag | Small project, API surface may shift |
| LibreChat | Docker tag pin | Fast-moving, breaking config changes between versions |
| firecrawl-simple | Docker tag pin | Breaking changes happen between releases |
| SWAG, MongoDB, Meilisearch | `latest` with caution | Mature projects, slower breaking change cadence |

A weekly dependency update checker (PM2 cron, Wednesdays at noon) scans for new versions and sends push notifications. It doesn't auto-update — you review changelogs before upgrading.

## Git Workflow: Direct-to-Main for Documentation Repos

**Choice:** Commit directly to `main` for documentation-only repos (context repo, prime directive). Feature branches and PRs for code repos.

Documentation repos change frequently with small, low-risk edits — memory-sync commits daily. A PR workflow would add friction without adding safety. Every commit is logged and easily revertible. Code repos use standard branch/PR workflow because code changes have higher blast radius.

## LibreChat Registration: Open Behind Authelia

**Choice:** Leave LibreChat registration open, rely on Authelia for access control.

With Authelia SSO in front of LibreChat, only authenticated users can reach the registration page. Open registration within LibreChat is useful for creating agent accounts or additional household users without needing to toggle settings. The authentication boundary is Authelia, not LibreChat.

## Web Search Pipeline: Self-Hosted SearXNG + firecrawl-simple + FlashRank

**Choice:** Full self-hosted search pipeline with zero recurring API costs.
**Alternatives considered:** Jina API, Cohere reranker API, Perplexity API, no web search.

LibreChat's built-in web search goes beyond MCP-based search (which only returns snippets) — it scrapes full page content, converts to markdown, and reranks by relevance before feeding to the model. The pipeline uses SearXNG for meta-search (already running for Perplexica), firecrawl-simple (Trieve's lightweight fork) for scraping, and a custom FastAPI wrapper around FlashRank for reranking. The FlashRank wrapper exposes Jina's API format so LibreChat thinks it's talking to Jina. Total RAM overhead is ~1.2GB. See the [LibreChat component doc](components/librechat.md) for the full breakdown.

---

## Related Docs

- [Architecture](architecture.md) — how the system connects
- [Getting started](getting-started.md) — setup order and stopping points
- [Component docs](components/) — per-service deep dives with implementation details
