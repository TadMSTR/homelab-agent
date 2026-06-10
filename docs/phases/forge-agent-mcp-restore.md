# Forge — Agent MCP Restore

**Completed:** 2026-05-26
**Snapshots:** (none — venv patches and config changes, no compose changes)

## What Was Built

Diagnosed and repaired the scoped-mcp framework that had never successfully started on
forge. Despite completing Phases 1–6 (infrastructure, agents, Matrix wiring), every
agent's scoped-mcp process was exiting on startup due to 3 independent incompatibilities
between scoped-mcp v1.0.0 and fastmcp 3.2.4. Five local patches to the scoped-mcp venv
resolved the incompatibilities; all 5 agents reached `server_ready` and tool proxying
was validated end-to-end.

On top of the core fix: all core MCP modules were restored to agent manifests, langfuse-mcp
was repaired, Claude Code → Langfuse tracing was wired via a Stop-hook, per-session
audit/ops logging was enabled flowing to Loki → Grafana, and OTel tool-call spans were
configured to export to SigNoz.

Phase 7 (hardening — tool denylist, rate limits, HITL) is deferred to research task **0fb2f48f**.

## Root Cause: fastmcp 3.x Incompatibilities

scoped-mcp v1.0.0 was written against fastmcp 2.x. Three categories of breaking changes in
fastmcp 3.2.4 each independently caused startup failure, requiring 5 patches total:

| Patch | File | Problem | Fix |
|-------|------|---------|-----|
| P1 | `mcp_proxy.py` | `ToolAnnotations` constructor rejects unexpected keyword args in fastmcp 3.x | Synthesize tool annotations from `inputSchema` fields |
| P2 | `mcp_proxy.py` | stdio-mode `mcpServers` config format changed — subprocess launch fails with old wrapping | Adopt fastmcp 3.x `mcpServers` wrapping format |
| P3 | `mcp_proxy.py` | `None` values in tool call results cause serialization errors in fastmcp 3.x | Strip `None` values from results before returning |
| P4 | `server.py` | OTel `TracerProvider` setup call signature changed | Update to fastmcp 3.x `TracerProvider` initialization |
| P5 | `middleware.py` | Tool signature passthrough broken — middleware didn't forward function signature correctly | Explicit signature copy in the passthrough handler |

All 5 patches are marked `# LOCAL PATCH (helm-build 2026-05-25)` in the venv source files
at `/opt/venvs/scoped-mcp/`. They are tracked in dev task **7e9b4c03**, which will port
them to the scoped-mcp source repo with the fastmcp pin corrected and a venv redeploy.

> **Note:** The `.orig-bak` and `.patched-bak` files left alongside patched files are
> intentional — they serve as the upstream patch submission reference for dev task 7e9b4c03.

## Launcher-Wrapper Pattern

A key finding: **stdio MCP subprocesses don't inherit the scoped-mcp environment.** Tools
that run as stdio subprocesses (langfuse-mcp) receive environment variables from
scoped-mcp's own runtime env, not from the agent's `settings.json` env block or
`forge.env`. Two launcher scripts were created to handle environment delivery:

**`~/scripts/run-scoped-mcp.sh`** — entry point for each agent's scoped-mcp session:
- Sources `~/.secrets/forge.env` and any per-agent secret files
- Creates per-session audit and ops log files under `~/.claude/logs/<agent>/`
- Execs `scoped-mcp` with the agent manifest path

**`~/scripts/run-langfuse-mcp.sh`** — launches langfuse-mcp as a stdio subprocess:
- Sources Langfuse credentials from `/opt/secrets/langfuse.env`
- Sets up the Langfuse environment before exec-ing the langfuse-mcp binary

Both scripts use `set -euo pipefail` (applied as part of L1 security fix).

## MCP Endpoint URL Corrections

Two MCP endpoints had incorrect URLs in all 5 agent manifests:

| Service | Incorrect URL | Correct URL | Note |
|---------|--------------|-------------|------|
| homelab-ops-mcp | `/mcp/` | `/mcp` | Trailing slash caused 404 |
| grafana-mcp | `/mcp` | `/sse` | grafana-mcp uses SSE transport, not streamable-HTTP |

Corrected in all 5 manifests.

## Module Restoration

With the venv patches in place and URLs corrected, the full module set was restored to
each agent manifest. The Matrix module (wired in the prior phase) and all fixed-URL
modules were re-enabled. Each agent now has its full intended tool surface:

| Module | Type | Auth | Agents |
|--------|------|------|--------|
| patchmon | mcp_proxy | Basic Auth + JWT dual-auth | all 5 |
| dockhand | mcp_proxy | Bearer token | all 5 |
| langfuse | mcp_proxy (stdio via run-langfuse-mcp.sh) | Basic Auth | all 5 |
| system-ops (homelab-ops-mcp) | mcp_proxy | HTTP | all 5 |
| matrix | mcp_proxy | MATRIX_ACCESS_TOKEN | all 5 |
| grafana | mcp_proxy | SSE `/sse` | sysadmin only |

## Observability Wiring

### Langfuse Stop-Hook

A Claude Code `Stop` hook (`~/.claude/hooks/langfuse_hook.py`) sends session metadata to
Langfuse after every agent session ends. Captures: session ID, transcript path, turn count,
token estimates, elapsed time. State is persisted at `~/.claude/state/` (dir: `chmod 700`,
files: `chmod 600` — L2 security fix).

The Dragonfly `allow-undeclared-keys` config option was required to unblock Langfuse
ingestion. BullMQ (used internally by Langfuse's queue) creates keys outside Langfuse's
declared schema, which Dragonfly rejects by default without this flag.

### Audit/Ops Logs → Loki → Grafana

Per-session audit logs (tool calls, permission gates) and ops logs (session lifecycle events)
are written by `run-scoped-mcp.sh` and fed through Grafana Alloy → Loki. A **"scoped-mcp
Tool Usage"** dashboard was created in the Forge Grafana folder.

Log label schema:
```
job=scoped-mcp   stream={audit|ops}   agent=<name>
```

### OTel Spans → SigNoz

OpenTelemetry tool-call spans export to SigNoz (deployed in the operator agents build).

- Service name: `scoped-mcp-<agent>`
- Covers: tool invocation, duration, success/failure
- Currently operator-facing only; no MCP surface for querying spans yet

## Security Audit Results

4 Low findings, all resolved.

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| L1 | Low | Launchers missing `set -e` — failed `mkdir` or `source` silently continued | Added `set -euo pipefail` to both `run-scoped-mcp.sh` and `run-langfuse-mcp.sh` |
| L2 | Low | `~/.claude/state/` files at 664 — contains session hashes and display names | `STATE_DIR.chmod(0o700)` in `langfuse_hook.py`; one-time `chmod 700` on dir + `chmod 600` on state files |
| L3 | Low | Langfuse SDK not pinned `< 5` in hook venv — accidental v5 upgrade breaks hook silently | Re-pinned `langfuse>=4.0,<5`; wrote `requirements.txt` in hook venv as a persistent record |
| L4 | Low | `middleware.py` signature propagation exception was silent `pass` — manifests as a missing tool at startup | Replaced with `_log.warning("middleware_sig_propagation_failed", ...)` |

No commits — all touched files are non-git-tracked (scoped-mcp venv, `~/.claude`, `~/scripts`).

## Deferred Items

| Ref | Scope | Details |
|-----|-------|---------|
| dev task **7e9b4c03** | Land patches in source | Port 5 venv patches to scoped-mcp source repo, correct fastmcp pin (`<3` → `>=3`), redeploy venv |
| research task **0fb2f48f** | Phase 7 hardening | Per-agent `tool_denylist` (note: `mode: read` is a no-op for `mcp_proxy` — capability restriction requires denylist), rate limits, HITL gates, agent-bus wiring |
| (untracked) | Forge backup coverage | Non-git agent config — manifests, `settings.json`, `langfuse_hook.py`, launchers, `/opt/secrets/langfuse.env` — should be added to forge's backup scripts to survive a rebuild |

## Related Docs

- [forge-agent-setup.md](forge-agent-setup.md) — agent project dirs, manifests, initial wiring
- [forge-matrix-agent-wiring.md](forge-matrix-agent-wiring.md) — Matrix token wiring
- [forge-operator-agents.md](forge-operator-agents.md) — prior phase: Langfuse, NATS, SigNoz deployed
- [scoped-mcp-forge.md](../components/scoped-mcp-forge.md) — scoped-mcp forge deployment (local patches)
