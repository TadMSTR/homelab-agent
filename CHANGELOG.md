# Changelog

Significant infrastructure additions and capability changes, in reverse chronological order. Documentation-only updates are omitted.

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
