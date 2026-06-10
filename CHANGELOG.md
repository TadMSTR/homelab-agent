# Changelog

## [Unreleased]

## 2026-05-28 — forge-q2-sync-deploy

repo-improvements-q2 updates deployed to forge. 5 MCP service repos pulled (agent-bus,
task-queue-mcp, pm2-mcp, memory-search-mcp, memory-metadata-mcp) and redeployed.
helm-temporal-worker renamed to temporal-build-worker. githost-mcp v0.1.0 deployed as a
per-agent subprocess MCP (developer + sysadmin); Python launcher at ~/scripts/run-githost-mcp.sh;
venv at /opt/venvs/githost-mcp/; AGENT_ID injected per-agent via manifest env block.
OQP upgraded v0.2.0 → v0.3.0 (new /v1/embeddings OpenAI-compat endpoint); graphiti
reconfigured to route embeddings through OQP (port 11434 → 11435). sync-forge-repos.sh
created for managed repo sync using transient token auth. 4 repos cloned (githost-mcp,
agent-activity, build-reports; agent-templates not yet created).

Security: 4 findings resolved — GITHUB_TOKEN removed from all .git/config remotes and
sync script patched (M1); NATS and Dragonfly containers hardened (L1, L2); githost-mcp
.gitignore updated upstream (L3). ~/repos/personal chmod 750. nats:latest pinned to 2.12.6.

## 2026-05-26 — scoped-mcp-phase7-forge

Phase 7 scoped-mcp hardening applied to all 5 forge agents. Per-agent tool denylists
enforce least-privilege (e.g. graphiti `clear_graph` blocked for non-sysadmin agents).
Rate limits added (global 60–120/min, per-tool for LLM-intensive and destructive calls).
sysadmin agent gains HITL gate (Dragonfly state backend + Matrix notification) for
container/service lifecycle tools. All 5 agents emit signed agent-bus audit events
(ed25519, private keys in Vault KV). Argument filters block path-traversal; credential-leak
and shell-injection rules in warn mode. Response filters redact API keys from tool outputs.
loki-mcp v0.1.0 deployed as read-only Loki query MCP for security and sysadmin agents.
scoped-mcp upgraded v1.0.1 → v1.2.0 (via git tag).

Security audit: 4 Low findings — L1 manifest gap fixed (research argument_filters added),
L2 OTel redaction bypass fixed (span.add_event in v1.1.1), L3 Vault wildcard policy fixed
(per-agent AppRoles + policies), L4 Dragonfly password moved to .env via v1.2.0 env var
substitution.

## 2026-05-26 — forge-agent-mcp-restore

Diagnosed and fixed the forge multi-agent framework: scoped-mcp v1.0.0 was incompatible
with fastmcp 3.2.4 in three ways, preventing all 5 resident agents from reaching
`server_ready`. Five targeted venv patches resolved the incompatibilities. Phases 1–6, 8,
and 9 then completed the MCP wiring: created per-agent `/ops` directories, installed the
Langfuse SDK (`[otel]` extra), and wired full observability — Langfuse traces,
audit/ops→Loki→Grafana, OTel→SigNoz. All 5 agents (sysadmin, research, developer,
writer, security) reach `server_ready` and proxy tools with Matrix posting intact.
Security audit: scoped-mcp hardening deferred to Phase 7.

Three items deferred: upstream source patches + fastmcp pin (dev track `7e9b4c03`),
Phase 7 hardening — tool_denylist least-privilege, rate-limits, HITL (research track
`0fb2f48f`), and non-git agent config coverage in forge backup scripts.

## 2026-05-25 — forge-patchmon-migration

Replaced PatchPilot with PatchMon as forge's apt patch-management layer. Deployed a
4-container PatchMon stack (server v2.0.2, postgres:17-alpine, valkey:8-alpine,
guacd:1.6.0) with native OIDC via Authentik and a plain SWAG reverse proxy (no
forward-auth — PatchMon handles its own JWT/OIDC auth). Forge host enrolled via
outbound-only PatchMon agent (1943 packages, 8 repos reported on first check-in).
PatchPilot fully decommissioned: container, host agent service, appdata archived, SWAG
conf removed. Security audit: 2 Low findings resolved (SHA digest pinning, archived
credential shredding).

## 2026-05-24 — forge-matrix-synapse

Deployed Matrix/Synapse communications backbone on forge: Synapse v1.153.0 + PostgreSQL
(digest-pinned), Ketesa admin UI (Authentik-gated), well-known delegation via SWAG
`default.conf`. Accounts: `@ted` admin + 5 agent bot accounts (`@forge-sysadmin`,
`@forge-research`, `@forge-developer`, `@forge-writer`, `@forge-security`). Eight rooms
created with full bot membership. Invite-token registration enabled for family access.
Services: matrix-mcp MCP server (PM2 `:8487`, registered in all 5 agent scoped-mcp
configs), matrix-dispatcher (PM2, polls all 5 agent rooms, stub config pending
forge-agent-setup), matrix-admin-bot (PM2, `!`-command admin control).
Security audit: 3 findings resolved (chmod 600 homeserver.yaml, Postgres digest pin, git
history scrub on matrix-dispatcher).

## 2026-05-24 — forge-update-management-phase1

Deployed forge's update management stack: Dockhand compose volume mount for stack
visibility, PatchPilot (apt package tracking, HTTPS UI at patchpilot.helmforge.me, agent
on port 8050 LAN-only), Renovate (non-Docker dependency scanner, hourly PM2 cron,
autodiscovering host-forge/stacks via Gitea). Gitea infrastructure: renovate-bot user + PAT,
host-forge/stacks topic tag, host-forge/component-registry repo with component YAML stubs.
Security audit: 4 findings resolved (rw→ro Dockhand mount, SHA image pinning, no-new-privileges,
UFW rule for port 8050).

## 2026-05-24 — forge-observability-stack

Activated forge's observability stack: InfluxDB 2 → InfluxDB 3 Core, added Telegraf
(system+Docker metrics), Prometheus (native /metrics scraping), Grafana Alloy (container
logs, replaces EOL Promtail), Grafana Image Renderer (AMD iGPU DRI), Grafana MCP (SSE on
:8014). All 8 images SHA-pinned; 3 security findings triaged (2 fixed, 1 accepted).

## 2026-05-16 — forge-operator-agents

Deployed operator agent infrastructure on forge (Dockhand, Hister, CloudCLI, memory-stack, Langfuse wiring). All five build phases (A–E) complete. Security audit: 8 findings, all resolved (1 High NATS rebind, 4 Medium, 3 Low including git history purge). Authentik forward auth active for all three user-facing services.

See [`docs/phases/forge-operator-agents.md`](docs/phases/forge-operator-agents.md) for full details.

## 2026-05-13 — forge-phase5-user-stack-infra

Deployed Phase 5 user stack infrastructure (Dragonfly, scoped-mcp, gateway runner). Security audit: 2 High findings resolved (WEBUI_SECRET_KEY, CRAWL4AI_API_TOKEN rotated), 3 medium/low auto-fixed, 3 low accepted.
