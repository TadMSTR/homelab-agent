# scoped-mcp Phase 7 — Forge Security Hardening

**Completed:** 2026-05-28

This build hardened the scoped-mcp layer for all 5 forge resident agents (research, developer,
writer, security, sysadmin). It added tool denylists, rate limits, HITL, audit signing, argument
and response filters, Vault per-agent AppRoles with ed25519 key storage, and claudebox cross-host
access. A security audit followed; 4 pre-existing findings were resolved and one was accepted with
documented risk.

## What Was Built

### Tool Denylists and Rate Limits

Each agent manifest received a `tool_denylist` block (least-privilege) and `rate_limits` block.
The sysadmin global limit is 60/minute; research and developer are 120/minute. High-cost tools
(`searxng-mcp_search_and_summarize`, `system-ops_run_command`, all dockhand/patchmon/pm2 tools)
have per-tool limits. See [scoped-mcp.md](../components/agent/scoped-mcp.md) for the full
table.

### HITL for sysadmin

The sysadmin agent now requires human approval before executing 6 high-impact tools
(`dockhand-mcp_container_action`, `dockhand-mcp_stack_action`, `dockhand-mcp_update_container`,
`patchmon-mcp_approve_patch_run`, `pm2-mcp_stop_service`, `pm2-mcp_restart_service`). Approval
notification goes to `#forge` via Matrix; approval itself is via `scoped-mcp hitl approve` CLI.
State is backed by Dragonfly at `127.0.0.1:6380`.

### Audit Trail (agent-bus + ed25519 signing)

All 5 agents emit structured tool call events to agent-bus with `log_args: true`. Private ed25519
signing keys are stored in Vault KV (`secret/data/agents/<type>`), loaded at agent startup by
`scoped_mcp.contrib.signing_hook`. Public keys are registered in
`~/.claude/comms/agent-keys.json` (644). agent-bus runs in `enforce` mode; unsigned events from
agents that haven't restarted yet are passed through silently.

### Vault Per-Agent AppRoles

Each agent authenticates to Vault via a dedicated AppRole with a policy scoped to read-only
access on `secret/data/agents/<type>` only. Credentials are in
`/opt/appdata/agents/<type>/.env` (chmod 600, never committed).

| Agent | AppRole | Policy |
|-------|---------|--------|
| research | `forge-research` | `agents-research-policy` |
| developer | `forge-developer` | `agents-developer-policy` |
| writer | `forge-writer` | `agents-writer-policy` |
| security | `forge-security` | `agents-security-policy` |
| sysadmin | `forge-sysadmin` | `agents-sysadmin-policy` |

### Argument and Response Filters

All 5 agents received 3 argument filter rules and 2 response filter rules. Only
`path-traversal` (`../`, `..\`) is a hard block; credential and injection patterns are `warn`
mode pending one week of production monitoring before promotion to block.

### claudebox-ops

Cross-host access to claudebox (<server-ip>) via homelab-ops-mcp at `:8282`. Wired for
research (read/run only — `write_file` and `edit_file` denylisted) and sysadmin (full access).

## Security Findings Resolved

| ID | Finding | Resolution |
|----|---------|------------|
| L1 | Manifest gap — memsearch-mcp not registered in all 5 agent manifests | Added memsearch-mcp `mcp_proxy` entry to all 5 manifests; `index_memory` denylisted for security, research, and writer |
| L2 | OTel `exception.message` not redacted | `_redact_string()` applied to `exception.message` and span status description; stacktrace suppressed entirely |
| L3 | Vault AppRole policy used wildcard path (`secret/*`) | Per-agent policies scoped to `secret/data/agents/<type>` read-only; `secret/metadata/agents/<type>` list+read |
| L4 | Dragonfly credential hardcoded in sysadmin manifest | Moved to `/opt/appdata/agents/sysadmin/.env` (600); manifest uses `${DRAGONFLY_URL}` env var expansion (v1.2.0+) |

## v1.2.2 Bug Fixes

Three silent bugs corrected during the same build window:

| Bug | Impact | Fix |
|-----|--------|-----|
| Double-prefix registry | `approval_required`, `per_tool`, and denylist patterns never matched — Phase 7 controls were silently inactive since deployment | Prefix applied once at the correct layer |
| agent-bus tilde expansion | Audit events written to `~/...` literal paths; reconciler and log shippers couldn't find them | `audit.py` uses `Path.expanduser()` before write |
| ManifestError secret suppression | YAML parse errors could surface expanded env var values (e.g., Vault secret IDs) to the agent | Generic "manifest load failed" returned; detail at debug log only |

## Audit Results

Post-build security audit by security-agent (2026-05-28). Full report:
`~/.claude/comms/artifacts/audit-reports/scoped-mcp-phase7-forge/report.md`

| Check | Result |
|-------|--------|
| SC-01: .env permissions (all 5 agents, vault.env) | PASS |
| SC-02: agent-keys.json permissions (644) | PASS |
| SC-03: Vault AppRole policy scope | PASS |
| SC-04: Path-traversal argument filter (block action, URL decode) | PASS |
| SC-06: OTel exception.message redaction | PASS |
| SC-07: loki-mcp read-only tool surface | PASS |
| SC-03: Vault AppRole `secret_id_ttl` / `secret_id_num_uses` unlimited | FLAG (PHASE7-01) |
| SC-05: HITL Matrix room smoke test | PENDING (manual) |

## Open Items

**PHASE7-01 (Low)** — Vault `secret_id_ttl: 0` and `secret_id_num_uses: 0`. Secret IDs never
expire. Individual token TTL is correctly limited (1h/4h max). Recommendation: accept risk —
single-user host, read-only policy, 600 permissions on .env files. Revisit if Vault is ever
network-exposed.

**SC-05 (Manual gate)** — HITL smoke test requires a live sysadmin session triggering an
`approval_required` tool (e.g., `pm2-mcp_restart_service`). Security agent cannot trigger this
from its manifest scope. Ted should verify the Matrix notification arrives in `#forge` and the
approval workflow completes before treating HITL as production-ready.

## Related Docs

- [scoped-mcp.md](../components/agent/scoped-mcp.md) — full deployment reference with manifest details
- [loki-mcp.md](../components/observability/loki-mcp.md) — read-only Loki query MCP (security + sysadmin)
- [vault.md](../components/foundation/vault.md) — Vault AppRole auth and KV setup
- [agent-bus.md](../components/agent/agent-bus.md) — audit event bus and ed25519 signature verification
- [dragonfly.md](../components/agent/dragonfly.md) — HITL state backend
