# docs/phases

Build history for the homelab-agent platform. Each doc records what was built, why, what changed, and any security findings resolved. Read in order for a complete picture of how the platform evolved.

Naming conventions:
- `forge-phase<N>-*` — early foundational forge phases
- `phase-<N>-*` — agent framework phases (4–7)
- `forge-*` — named forge builds
- `*-<YYYY-MM>` — dated standalone builds

---

## Foundational Phases

| Doc | What was built |
|-----|---------------|
| `forge-phase1-gitea-setup.md` | Gitea org and repo setup on Atlas |
| `forge-phase2-kb-seeding.md` | Knowledge base seeding |
| `forge-phase4-stack-reorg.md` | Stack reorganization |
| `forge-phase5-user-stack-infra.md` (see `phase-5-user-stack-infra.md`) | User-facing stack infrastructure |

## Agent Framework Phases

| Doc | What was built |
|-----|---------------|
| `phase-4-agent-framework.md` | Agent framework — NATS, per-agent credentials, task routing |
| `phase-5-agent-isolation.md` | Unix user isolation, per-agent file permissions and credential scoping |
| `phase-5-user-stack-infra.md` | User stack infrastructure (Vaultwarden, Authentik, SWAG) |
| `phase-6-system-agents.md` | System agents — sysadmin, research, developer, writer, security |
| `phase-7-agent-infrastructure.md` | Agent infrastructure hardening — scoped-mcp, Vault, signing |
| `scoped-mcp-phase7-forge.md` | scoped-mcp Phase 7 security hardening — denylists, HITL, rate limits, audit |

## Named Forge Builds

| Doc | What was built |
|-----|---------------|
| `forge-operator-agents.md` | Operator agent platform setup |
| `forge-observability-stack.md` | Grafana, InfluxDB, Telegraf, SigNoz, Langfuse |
| `phase-analytics-stack.md` | Analytics stack (ClickHouse, Langfuse, MinIO) |
| `phase-matrix-synapse.md` | Matrix/Synapse homeserver, Matrix MCP, dispatcher |
| `forge-matrix-agent-wiring.md` | Matrix agent wiring and room setup |
| `forge-agent-setup.md` | Full agent setup — manifests, scoped-mcp, Phase 7 hardening |
| `forge-agent-mcp-restore.md` | Agent MCP restore — venv fixes, observability wiring |
| `forge-memory-migration-2026-05.md` | Memory pipeline migration from claudebox to forge |
| `forge-update-management-phase1.md` | Renovate, Woodpecker CI, patchmon setup |

## Standalone Builds (Dated)

| Doc | What was built |
|-----|---------------|
| `btrfs-snapshot-management-2026-05.md` | Btrfs snapshot management automation |
| `woodpecker-forge-2026-05.md` | Woodpecker CI deployment on forge |
| `forge-memory-migration-2026-05.md` | Memory system migration (May 2026) |
| `memsearch-summarize-2026-06.md` | memsearch-summarize deployment and configuration |
| `temporal-workflow-trigger-2026-06.md` | Temporal workflow trigger integration |
| `agent-workspace-forge-2026-06.md` | Agent workspace isolation and pre-warming |
