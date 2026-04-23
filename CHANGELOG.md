# Changelog

Significant infrastructure additions and capability changes, in reverse chronological order. Documentation-only updates are omitted.

---

## 2026-04-23

**Matrix agent communications stack** — Deployed a Synapse v1.151.0 + PostgreSQL 16 + Element Web v1.12.15 homeserver as the primary agent notification and communication layer. Replaces ntfy for most events; ntfy is retained only for pending-approval and dead-letter notifications.

Two new public repos: [`matrix-mcp`](https://github.com/TadMSTR/matrix-mcp) (FastMCP HTTP server, port 8487, `127.0.0.1` only) and [`matrix-channel`](https://github.com/TadMSTR/matrix-channel) (Node.js Claude Code Channel plugin). `matrix-mcp` exposes four tools to agents: `send_matrix_message`, `post_artifact`, `get_matrix_messages`, `list_matrix_rooms`. `matrix-channel` polls a Matrix room and injects operator replies as user input into an active Claude Code session, enabling permission relay without a separate chat window.

11 rooms — one per agent (`#claudebox`, `#dev`, `#homelab-ops`, `#research`, `#security`, `#helm-build`, `#pr`, `#writer`, `#memory-sync`) plus `#announcements` and `#general`. `task-dispatcher.py` updated with a `matrix_notify()` routing helper: submit/approve/reject/complete/handoff events now post to Matrix rooms instead of ntfy. 9 agent `CLAUDE.md` files updated with `## Communications` sections specifying room assignments.

**Security hardening (7 findings resolved):** SWAG proxy blocks `/_synapse/admin/` with 403 (M1); `homeserver.yaml` set to mode 640 (M2); `post_artifact` allowlist pruned to `~/repos/`, `~/.claude/comms/`, `~/.claude/memory/` — `/opt/appdata/` and Docker compose trees removed (M3); `html.escape()` applied to title in `formatted_body` (L1); `bleach.clean()` with Matrix-spec allowlist wraps all markdown rendering (L2); `</claude-channel>` tag-boundary injection escaped in matrix-channel (L3); Docker Compose hardening flags added — `no-new-privileges:true`, `cap_drop: ALL`, memory limits per container (L4).

---

## 2026-04-22

**ollama-queue-proxy v0.2.0 deployed** — Upgraded from v0.1.2 to v0.2.0 (Smart Pool Manager). Five new capabilities now live on claudebox: port-based client injection (memsearch-watch reaches the proxy on `127.0.0.1:11436` with no Bearer header — identity injected as `memsearch-watch` by the proxy); model-aware weighted round-robin routing (proxy polls `/api/tags` every 30s and routes to the host already holding the requested model); SHA256-keyed Valkey embedding cache (24h TTL, `/api/embed` + `/api/embeddings` deduplicated); `keep_alive: "5m"` defaulting to prevent model unloads between bursty requests; per-client concurrency cap (`max_concurrent: 2` on `memsearch-watch`). Valkey added as a dedicated sidecar container on an internal-only Docker network (`oqp-internal`). `deploy-claudebox.sh` updated so the queue-proxy stack auto-starts on rebuild.

---

## 2026-04-21

**ollama-queue-proxy public release** — Published [`TadMSTR/ollama-queue-proxy`](https://github.com/TadMSTR/ollama-queue-proxy) as a new public showcase repo. Smart pool manager for Ollama: per-client API keys with individual priority ceilings (`max_priority: low/normal/high`), three-tier priority queuing (high › normal › low) with per-tier depth limits and expiry, model-aware weighted round-robin routing across multiple Ollama hosts, SHA256-keyed Valkey embedding cache (24h TTL, `/api/embed` + `/api/embeddings` only), port-based client injection for clients without Bearer header support, and `keep_alive` defaulting to prevent model unloads between bursty requests. Security-first design: management endpoints (`/queue/pause`, `/queue/drain`, etc.) require a separate management key; per-client concurrency caps prevent batch workloads from starving interactive ones; webhook SSRF protection covers IP literals and hostnames. Drop-in compatible — point any Ollama consumer at the proxy port with one config change.

---

## 2026-04-20

**Hister memory search** — Self-hosted semantic + keyword search engine deployed over the Claude memory corpus and knowledge files. Provides browser-based search independent of live Claude sessions, covering ~500 files: agent memory, prime-directive, build plans, and platform docs. Semantic search uses `nomic-embed-text` via Ollama on forge; keyword search uses Bleve full-text indexing; SearXNG fallback fires on zero results. Web UI served at a private subdomain behind Authelia SSO; MCP endpoint at `/mcp` for programmatic access. Stack runs as a single container on `claudebox-net`, port 4433 internal-only; compose + `data/config.yml` (access token) added to backup/deploy scripts.

**Hister preview shim** (`scripts/hister-preview.py`) — Python HTTP service (PM2, port 4434) that intercepts Hister's `/api/preview` requests and renders markdown files as styled HTML, replacing a `chromedp` (headless Chrome) dependency not available in the container image. Fetches the raw file via Hister's `/api/file` endpoint, strips YAML frontmatter, converts with the Python `markdown` library, and returns JSON matching Hister's preview response schema (`{title, content, html, htmlType}`). SWAG routes `/api/preview` to the shim before it reaches the Hister container. Covered by the `~/scripts/` rsync in backup.

---

## 2026-04-12

**Automation infrastructure** — Wires the full autonomous multi-agent workflow pipeline. `trigger-proxy` new always-on Python service (`172.18.0.1:5679`) that lets n8n Docker workflows fire Claude Code RemoteTrigger sessions; reads OAuth token from `~/.claude/.credentials.json` with auto-refresh and proxies to `api.anthropic.com/v1/code/triggers/{id}/run`. `task-dispatcher` updated to post to n8n's task-approved webhook on approvals and move TTL-expired tasks to a `dead-letters/` subdirectory. Agent manifests added for dev and writer agents (capabilities, model pins, `interaction_permissions`); RemoteTrigger IDs for 8 agent variants stored at `~/.claude/agent-manifests/.trigger-map.yml`. Model pins locked in `settings.json` for 7 agent project chats (Sonnet for 6, Opus for security). Two new Gitea repos: `build-reports` (structured phase output per build) and `agent-activity` (task history, workflow digests, drift logs); both added to `repo-sync-nightly` and `qmd` semantic indexing.

**Security hardening** — Audit findings applied to trigger-proxy and task-dispatcher. `trigger-proxy` `/fire-trigger` endpoint now requires an `X-Trigger-Secret` header validated with `secrets.compare_digest` (loaded from `TRIGGER_PROXY_SECRET` env var) — prevents timing attacks and unauthorized invocations from n8n or any caller without the shared secret. `do_POST` enforces a 65536-byte body size cap to prevent request amplification. `save_credentials()` switches to `os.open(..., 0o600)` so `credentials.json` is always written at mode 0600 — prevents silent downgrade to 0644 on token refresh. `task-dispatcher`'s `atomic_write()` uses the same `os.open(..., 0o600)` pattern for all task queue YAML files.

**Docker Compose templates** — 11 missing sanitized stack templates added to `docker/`: grafana, graphiti, milvus, n8n, nats, plane, temporal, crawl4ai, searxng-mcp-cache, task-queue-mcp, blog-preview. Real domains, host paths, and API tokens replaced with generic placeholders throughout. Secrets-bearing stacks include a paired `.env.example`; supporting configs included where needed (graphiti `config.yaml` + Dockerfile, milvus `embedEtcd.yaml`, nats `nats-server.conf`, temporal namespace and PostgreSQL setup scripts, `dynamicconfig/`). `docker/open-notebook/` removed — stack retired. Docker stacks table updated 10 → 20. `.gitignore` updated with `!.env.example` so example files are tracked.

---

## 2026-04-08

**jobsearch-mcp v2** — Major rebuild of the job search platform. Voyage AI replaced with Ollama `bge-m3` for all embeddings — same model as memsearch and Graphiti, no external embedding API dependency. Valkey added as an enrichment cache (key: `job:enrich:<url>`) — repeat JD fetches are instant. Enrichment pipeline upgraded to three tiers: Firecrawl → Crawl4AI → rawFetch, matching the searxng-mcp fetch cascade pattern. Five new **Resume Profile** tools added: `build_profile` (Claude-powered resume parser), `save_profile`, `get_profile`, `delete_profile`, `tailor_resume` — stored profiles are used automatically by `score_fit` and `cover_letter_brief` when no resume text is passed. `score_fit` now returns an ATS score alongside the existing skills/gaps/recommendation output. Three new job sources: USAJobs (government listings, now a default source), Findwork, and The Muse (both optional). `job-watcher` Docker service added — polls Adzuna, RSS feeds, and USAJobs on a configurable interval, matches results against each user's stored profile, sends SMTP email alerts for new matches via Valkey-backed deduplication. `server.py` refactored from a monolithic tool registry to a thin dispatcher with tool logic split into `src/tools/` modules. Security hardening: `_validate_url` restricted to HTTPS-only to prevent SSRF. Stack grew from 3 → 5 containers (added Valkey, job-watcher). Qdrant `jobs` collection requires drop+recreate on upgrade — embedding space changed.

**searxng-mcp v3.1.0** — Recency weighting added to the reranker pipeline. Results can be boosted by freshness using exponential decay (90-day half-life). `RERANK_RECENCY_WEIGHT` (0.0–1.0) blends recency score with the semantic score at re-rank time; set to `0.0` to disable. Startup validation rejects NaN, negative, or > 1 values with a clear error. Complements the existing `RERANK_TOP_K` and model selection controls.

**pm2-mcp** — New FastMCP server wrapping the PM2 CLI. Six tools: `list_services` (with optional status filter), `get_service` (full detail including script path, log files, created_at), `get_logs` (tail with configurable line count), `restart_service`, `stop_service`, `start_service`. Uses `pm2 jlist` for structured JSON output — no screen-scraping. Write tools validate service names before acting. Binds to `127.0.0.1:8486` (localhost only); runs as PM2 id 26.

**ntfy-mcp** — New FastMCP server for ntfy push notifications. One tool: `send_notification` with full ntfy header support (title, priority, tags, markdown, click URL, icon). Runs as a Docker container (port 8484). Wired into both Claude Code (`~/.claude/settings.json`) and LibreChat (`librechat.yaml`). Replaces ad-hoc curl invocations in agent workflows — every agent now has a native `send_notification` tool call.


---

## 2026-04-06

**memsearch v0.2.x** — Major embedding stack upgrade. Milvus Lite replaced with a Milvus standalone Docker container (`localhost:19530`) — more stable under concurrent writes and easier to manage as a named volume. Embeddings now generated by `bge-m3` (1024-dim, 8192-token context) via a remote Ollama instance on the forge GPU, replacing `nomic-embed-text`. The extra context window means files that previously failed to index (512-token limit under nomic) now index successfully. A cross-encoder reranker (`gte-reranker-modernbert-base`) re-scores results after retrieval. The `compact` command consolidates the global session store and purges low-value entries; model history is tracked for audit. Each embedding model transition requires a full re-index: stop Milvus, clear the data volume, restart, run `memsearch index`. The `OLLAMA_HOST` env var is the only way to configure the Ollama endpoint — the config file's `base_url` field is ignored by the Ollama provider. Hardcoded in the watch and compact PM2 scripts.

**Graphiti embedder switch** — Voyage AI replaced with `bge-m3` via the Ollama OpenAI-compatible endpoint on the forge GPU. Eliminates the Voyage AI API dependency; both memsearch and Graphiti now use the same embedding model and the same GPU-backed Ollama instance. Config change is in `config.yaml` under `embedder.provider: openai` pointing at the forge Ollama URL. Full graph rebuild not required — new episodes use the new embeddings; existing nodes retain their old vectors until they're next touched.

---

## 2026-04-04

**searxng-mcp v3.0.0** — Major feature release across the v2.1.0 → v3.0.x series. v2.1.0 added Valkey result caching (1-hour TTL for search results, 24-hour TTL for URL fetches) and configurable domain boost/block profiles. v3.0.0 added the `search_and_summarize` tool (search + fetch + Ollama qwen3:14b structured summarization with citations) and an `expand` parameter for query rewriting via Ollama qwen3:4b before SearXNG submission. v3.0.1 and v3.0.2 fixed the Crawl4AI fetch cascade behavior (proper fallback from Firecrawl → Crawl4AI → raw HTTP). v3.0.3 added `CRAWL4AI_API_TOKEN` auth support and an empty-response cascade fix so a successful but empty Crawl4AI response falls through to raw HTTP rather than returning nothing. GitHub URLs in `search_and_fetch` bypass the cascade and use the GitHub API directly.

---

## 2026-04-02

**doc-sync** — Documentation cache system. `doc-sync.py` runs as a PM2 cron at 3 AM daily, reading `~/docs/doc-sync.yml` (service → topic → URL catalog), fetching official docs, converting HTML → markdown via html2text, chunking at H2/H3 headings, and writing chunks to `~/.claude/memory/docs/<service>/`. Each chunk carries `type: doc-cache` frontmatter so it's distinguishable in memsearch results. `memsearch-watch` picks up new chunks within 5 seconds — no manual reindex step. 42+ services covered. `cache-manifest.md` is rewritten after each run with a sync summary. Agents query the cache with `memsearch search "<service> <topic>"` instead of fetching live URLs — eliminates network dependency and per-fetch token cost.

**helm-ops MCP** — SSH-based FastMCP MCP server for the helm-build agent (`TadMSTR/helm-ops-mcp`). Provides remote shell execution and filesystem operations (`run_command`, `read_file`, `write_file`, `edit_file`, `read_directory`, `upload_file`) on the Helm target host over SSH, plus read-only local access to build plans and memory on claudebox (`local_read_file`, `local_read_directory`). The local tools are allowlist-restricted to helm-platform repo, build plans, and memory — no writes to claudebox from the Helm build context. Port 8283, localhost only. Mirrors the homelab-ops tool surface so the helm-build agent uses the same patterns regardless of which host it's targeting.

**librarian-weekly** — Monday 6 AM PM2 cron running a headless Sonnet session to keep the prime-directive repo in sync with actual system state. Compares skills on disk against the repo's `index.md`, finds missing entries, checks for stale metadata, and auto-commits additive changes. Judgment calls (conflicts, significant content drift) are flagged in an ntfy notification rather than auto-committed. Runs alongside `memory-sync-weekly` as part of the Monday morning maintenance window.

**repo-sync-nightly** — PM2 cron at 23:30 daily that applies a two-track policy to all personal repos: doc repos (homelab-agent, prime-directive, helm-platform, grafana-dashboards, TadMSTR profile, blog) auto-commit and push agent-generated changes with a timestamped `chore: agent sync` message; code repos fire an ntfy alert listing uncommitted or unpushed work for human review. Never auto-commits code.

---

## 2026-03-29

**Temporal + Helm Temporal Worker** — Temporal 1.30.2 deployed as a 5-container Docker stack (`temporal-postgresql`, `temporal-admin-tools` init, `temporal`, `temporal-create-namespace` init, `temporal-ui`). Provides durable workflow execution for multi-phase Helm build automation — each build phase becomes a Temporal workflow activity with structured retry policies, replacing brittle script chains. gRPC API on `127.0.0.1:7233` (localhost only); UI proxied at `temporal.yourdomain` behind Authelia. The two init containers are idempotent (`|| true` on create-database and namespace create) so `docker compose up` restarts safely. A dedicated `helm-temporal-worker` PM2 service bridges Temporal to Claude Code agents via the async activity completion pattern: the worker writes a task YAML to `~/.claude/task-queue/`, calls `raise_complete_async()` to park the activity, and exits. The agent picks up the task at session start via `inject-task-queue.sh`, executes the phase, then signals completion via `temporal-complete <task_token> success`. Temporal advances to the next phase. This decouples interactive agent sessions — which can take hours — from the synchronous activity execution model.

**Agent Bus** — FastMCP MCP server (`TadMSTR/agent-bus-mcp`) providing a unified inter-agent event log. Agents call `log_event` with an event type, source, target, summary, and optional artifact path. Events append to daily JSONL files in `~/.claude/comms/logs/` and are federated to NATS JetStream (`agent-bus.{hostname}.events`) inline and via a 30-second background loop with a file+offset cursor for gap-fill on NATS downtime. Consumers should treat the stream as at-least-once; the AGENT_BUS stream has a 2-minute dedup window. High-priority event types (`task.failed`, `handoff.created`, `audit.requested`) also fire ntfy alerts. Three PM2 services: `agent-bus` (always-on server + federation loop), `agent-bus-reconcile` (every 5 minutes — scans `artifacts/` for files with no log entry), `agent-bus-cleanup` (3:50 AM — prunes JSONL files older than 90 days). `agent_bus_client.py` provides a direct-write Python path for PM2 scripts that can't call MCP. Skills wired: `build-close-out`, `security-audit`, `diagnose`, `memory-flush`, `build-plan-review`; `task-dispatcher.py` uses the Python client.

**Memory pipeline tiered schedule** — The monolithic nightly memory-sync split into three jobs by cost and cadence. `memory-promote-daily` runs at 11 PM every night with Haiku, executing Steps 1–3 (session → working tier promotion). `memory-sync-weekly` runs Monday at 7 AM with Opus, executing Steps 4–8 (working → distilled distillation, graph ingestion, entity dedup). The original `memory-pipeline` orchestrator continues at 4 AM daily for `memsearch-compact` + `qmd-reindex`. Reduces weekly Opus API cost significantly — distillation only runs once per week on the accumulated week's working notes rather than nightly. The memory-pipeline timeout was also tightened from 1800s → 1500s.

**memsearch-watch and archival-search** — `memsearch-watch` PM2 service watches `~/.claude/memory/` with a 5-second debounce; any new or updated markdown file is indexed incrementally without requiring a full `memsearch index` run. `archival-search` skill added as the recommended default search path — queries session tier (memsearch), working tier (qmd), and distilled tier (qmd prime-directive collection) and returns merged results with tier labels. Replaces ad-hoc invocations of memsearch and qmd separately.

---

## 2026-03-28

**Helm Dashboard CloudCLI plugin** — Browser-based monitoring tab added to CloudCLI for walk-away agent builds. Eight panels covering active agent sessions, memory browser, handoff queue, knowledge graph queries (Graphiti Streamable HTTP), PM2/Docker infrastructure status, build plan progress, Plane work items, and WebSocket live updates via file watchers. Vanilla TypeScript with esbuild-bundled frontend; ws library for the WebSocket server. Deployed to `~/.claude-code-ui/plugins/` — symlinks don't work, must copy. Re-deploy after CloudCLI npm updates. SWAG conf gains a `/plugin-ws/` location block (Authelia-exempt, same model as existing `/ws` path).

**Auto mode configuration** — Claude Code auto permission mode enabled for walk-away builds. Global `~/.claude/settings.json` holds environment rules for trusted operations (reads, safe git/observability commands, scoped MCP tools, ntfy). Per-project `~/.claude/projects/helm-build/settings.json` adds helm-ops MCP SSH permissions scoped to that workflow only. CloudCLI SDK patch defaults new sessions to auto mode — the frontend doesn't expose `permissionMode`, so `server/claude-sdk.js` is patched to default to `'auto'` when no mode is set. Patch must be re-applied after each CloudCLI npm update; script at `~/scripts/patch-cloudcli-auto-mode.sh` is idempotent and requires sudo. Patch was updated post-security-audit to scope auto mode to sessions with a CLAUDE.md present (managed agents only).

**Human-gated pipeline extensions** — Five-phase extension to the inter-agent coordination stack. Phase 2: `~/.claude/pending-actions/` directory and `inject-pending-actions.sh` SessionStart hook — agents write blocking decisions to disk, send ntfy, and move on rather than waiting idle; stale items caught by resource-monitor every 6 hours. Phase 5: `~/.claude/agent-status/` directory, `inject-agent-status.sh` SessionStart hook, and `update-agent-status.sh` helper — each agent maintains a live status file that gives all other agents and the operator a shared pipeline view (recent activity capped at 5 entries). Phase 1: structured `report.md` schema in the security-triage skill — machine-parseable findings with `severity`, `category`, `action`, `status` (resolved/unresolved/context-dismissed), and `resolution` fields; extended audit lifecycle adds `report-written`, `pending-fixes`, and `fixes-complete` states. Phase 3: severity-gated fix workflow in building agents — critical findings block immediately with ntfy, high findings prompt Ted, low/medium Category A findings auto-fix; `context-dismissed` lets builders flag false positives for security spot-check. Phase 4: `build-report` entry type added to the doc-update-queue and `build-close-out` skill — the writer agent reads the referenced report and build plan, updates relevant docs, and marks the entry done. No new PM2 processes or Docker containers — all file-based. Settings.json now has five SessionStart hooks.

---

## 2026-03-27

**Plane project management (Phase 1)** — Plane deployed as an 11-container Docker stack for tracking the Helm platform build. Frontend (Next.js), admin panel, shared spaces, and live collaboration servers sit behind a multi-path SWAG proxy conf with Authelia on all routes. Backend runs Django API + Celery workers with RabbitMQ as the task broker, PostgreSQL for storage, Valkey for cache/sessions, and MinIO for S3-compatible file uploads. Localhost API port (8180) exposed for MCP and internal tooling without SSO overhead. `plane-mcp-server` (55+ tools via PyPI/uvx) provides full workspace read/write from Claude Code sessions. Backup/deploy integration covers compose, secrets (`SECRET_KEY` is critical for restore), and SWAG proxy conf. Phase 2 (board population) and Phase 3 (custom webhook agent) are pending.

---

## 2026-03-21

**n8n workflow engine** — n8n 2.13.2 + Postgres 16 deployed as a webhook-triggered workflow engine for agent task routing. The PM2 dispatcher posts task submissions to n8n's `/webhook/task-submitted` endpoint, where a visual workflow handles risk-based gating: high-risk or approval-required tasks trigger ntfy push notifications, low-risk tasks pass through. n8n has direct read-write access to the task queue and read-only access to agent manifests via volume mounts. SWAG proxy at `n8n.yourdomain` uses n8n's built-in auth (not Authelia) so webhook endpoints remain reachable without SSO cookies. Workflow exports are version-controlled in `~/docker/n8n/workflows/`. Fire-and-forget integration — the file queue operates normally if n8n is unavailable.

---

## 2026-03-19

**NATS JetStream event bus** — NATS 2.10 deployed as an additive event transport for agent orchestration. Task state transitions from the dispatcher (`tasks.submitted`, `tasks.approval-requested`, `tasks.approved`, `tasks.failed`) and session-start hook (`tasks.working`) are published as JetStream subjects. Two streams: TASKS (30-day retention, `tasks.>`) and AGENT_EVENTS (7-day retention, `agents.>`, reserved for future use). Monitoring dashboard proxied at `nats.yourdomain` behind Authelia. File queue remains authoritative — NATS is fire-and-forget and the queue operates normally if NATS is unavailable.

---

## 2026-03-17

**Graphiti knowledge graph** — Neo4j 5.26.0 + Graphiti MCP temporal knowledge graph deployed as a Docker stack. Custom Dockerfile extending `zepai/knowledge-graph-mcp:1.0.2-standalone` with Anthropic and Voyage AI packages. Claude Sonnet handles entity extraction against a prescribed ontology (Service, Host, Network, Configuration, Agent, User, Port); Voyage AI voyage-3-lite generates embeddings. Neo4j browser proxied through SWAG behind Authelia. Graph is fed automatically by memory-flush (real-time during sessions) and memory-sync Step 5b (nightly batch with content hash manifest for dedup). Agents query the graph with `search_memory_facts` and `search_nodes` for infrastructure topology and relationship queries that flat-file memory can't answer.

**Memory-sync graph ingestion (Step 5b)** — The nightly memory-sync pipeline gained a new step after distillation: batch ingestion of touched notes into the knowledge graph via Graphiti MCP. Uses a content hash manifest (`graph-ingested.json`) for idempotency. Pipeline timeout increased from 600s to 1800s to accommodate per-note LLM and embedding calls. Non-blocking on Graphiti failures — the rest of the pipeline continues if the graph is unavailable.

---

## 2026-03-16

**Agent Workspace Protocol** — `AGENT_WORKSPACE.md` markers at seven filesystem roots enforce a two-party permission model: agent manifests declare what they claim to need, directory markers declare what's allowed, the stricter of the two wins. Hourly PM2 cron (`agent-workspace-scan`) validates markers, auto-commits drift in git-backed paths, cross-references all agent manifests for CIA-triad conflicts, and emits structured events to InfluxDB and Loki. Pre-edit resolver skill (`agent-workspace-check`) gates `git-config-tracking` and blocks edits on uncovered paths with an ntfy alert. Rogue agent detection wired; threshold currently at 0 pending baseline calibration.

**Local observability stack** — Loki 3.4.2, grafana-image-renderer, and Alloy dual-destination log shipping added to the claudebox grafana stack. Infrastructure logs continue to atlas Loki; self-healing agent logs route to local Loki only. Every PM2 background agent writing to `/var/log/claudebox/` is automatically queryable at `{job="self-healing"}` without touching the homelab-wide log instance.

**qmd 2.0.1** — Upstream bug qmd#140 resolved. Dropped the `lex`/`vec`-only MCP workaround — full hybrid `query` type now works over stdio transport. Node.js minimum bumped to 22+.

---

## 2026-03-15

**Agent orchestration** — Task queue in `~/.claude/task-queue/` with a PM2 dispatcher running every 2 minutes. Routes submitted tasks via capability-matched agent manifests, gates anything above the target agent's `max_auto_risk` at `pending-approval`, and surfaces approved tasks via a SessionStart hook. `task-approve` CLI for human review from the terminal or phone. `interaction_permissions` in manifests declares trust between specific agent pairs explicitly, not just inferred from risk level.

**Memory pipeline orchestrator** — Replaced three independent PM2 crons (memory-sync, memsearch-compact, qmd-reindex) with a single `memory-pipeline` job running them in sequence each night at 4 AM. Fixed a lock guard bug that was silently skipping compaction when called from within the pipeline. Memory-sync gained quarantine for notes with invalid frontmatter, configurable stale threshold (14 days), and a per-run audit log.

**Security agent** — Dedicated Claude Code project for post-build security audits. Building agents write audit requests to a shared queue after deploying; the security agent triages into auto-fix, discuss, and action-plan categories, and routes fixes back via the task queue. First bidirectional inter-agent workflow in the stack.

**Panel dep-updates** — The claudebox-panel tracks 7 stack dependencies, applies safe updates as background PM2 tasks, delegates complex updates to Claude Code with a pre-filled prompt, and keeps an audit log of everything applied or deferred.

---

## 2026-03-14

**Doc-health agent** — Headless Opus session runs weekly (Sunday 11 PM) as a PM2 cron. Checks for undocumented PM2 services, index drift, sanitization issues, structural integrity, and coverage gaps. Writes a `doc-update-queue.jsonl` that building agents read to dispatch post-build documentation tasks automatically — closing the loop between infrastructure changes and docs.

**Core-context memory tier** — Always-visible 40-line context block injected at every session start via SessionStart hook. Sits above the compression threshold so key facts about the environment, active projects, and recent decisions never scroll out of context mid-session.

---

## 2026-03-13

**CloudCLI** — Browser-based Claude Code interface with file explorer, multi-session tabs, git integration, and push notifications. Replaced CUI as the primary day-to-day interface. Runs as a PM2 Node.js process proxied through SWAG.

**Config version control** — Git tracking for `~/scripts/`, `~/docker/`, and `/opt/appdata/` via two Gitea repos. `git-config-tracking` skill wraps the pre-edit/post-edit commit workflow so config changes are automatically versioned without thinking about it.

---

## 2026-03-10

**SearXNG standalone** — Replaced Perplexica with a direct SearXNG + Valkey stack. Added firecrawl-simple for full-page content fetching and a Python reranker wrapper that scores results before they reach the LLM.

**LibreChat metrics** — Metrics exporter endpoint added to LibreChat. Telegraf scrapes conversation volume and model usage; data flows into the local InfluxDB alongside Claude Code session metrics for unified agent observability dashboards.

**qmd-repo-check** — PM2 cron (daily 9 AM) that scans the repos directory for new clones not yet in the qmd index. Auto-adds repos matching configured keywords; sends a push notification for anything else so the index never silently falls behind.

---

## 2026-03-09

**Initial public release** — homelab-agent published as a sanitized reference implementation of an AI-powered homelab operations platform. Docs cover all three layers: host tooling and MCP servers, self-hosted service stack, and multi-agent Claude Code engine.

## [Unreleased] — 2026-04-23

### Added

- **Matrix agent communications stack** — Synapse v1.151.0 Matrix homeserver + PostgreSQL 16 + Element Web v1.12.15 deployed on claudebox. Accessible at `matrix.<your-domain>` (Synapse) and `element.<your-domain>` (Element Web) via SWAG. Federation and public registration disabled; single-user internal deployment.
- **matrix-mcp** — FastMCP HTTP server (port 8487, loopback only) providing `send_matrix_message`, `get_matrix_messages`, `list_matrix_rooms`, and `post_artifact` tools to all Claude agent sessions via global `~/.claude.json` MCP registration.
- **matrix-channel** — Node.js Channel plugin (matrix-js-sdk v34) enabling two-way messaging in interactive Claude Code sessions. Watches `#approvals`, `#task-queue`, `#announcements`, and `#dev` rooms. Trusted-sender filter: `@ted:<your-server-name>` only. Supports permission relay for remote task approval via Element.
- **11 agent rooms** — `#task-queue`, `#approvals`, `#research`, `#claudebox`, `#dev`, `#helm-build`, `#homelab-ops`, `#security`, `#pr`, `#writer`, `#announcements`. Bot user `@claude-agent:<your-server-name>` joined to all rooms.
- **Matrix routing in task-dispatcher** — `matrix_notify()` function routes state transitions to Matrix: pending-approval → `#approvals` + `#task-queue`; auto-approved → `#task-queue`; stale/dead-letter → `#task-queue`. ntfy retained for pending-approval and dead-letter only.
- **## Communications section** added to all 9 agent `CLAUDE.md` files with room assignments.

### Fixed

- **task-dispatcher.py** — `archive_expired()` raised `TypeError` when `created` field was a bare date string (e.g. `2026-04-23`). `datetime.fromisoformat()` returns a naive datetime for date-only strings; now localized to UTC before comparison with timezone-aware `now`.
