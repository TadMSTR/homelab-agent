# Build: agent-workspace-forge-2026-06

**Date:** 2026-06-03
**Agent:** sysadmin (build), security (audit)
**Status:** Complete

---

## Summary

Ported the `AGENT_WORKSPACE.md` marker file protocol from claudebox to forge. Places machine-readable ownership and access declarations at 25 directory roots. Enables the source domain check in the planned `memory-eval-poisoning-2026-06` build — this is a direct prerequisite. Also created the `forge-configs` repo for non-secret config tracking, with Vault KV backing for `.env` secrets.

---

## What Was Built

### AGENT_WORKSPACE.md markers (25 roots)

Marker files written at all agent-editable directory roots. Schema is identical to the claudebox version:

```yaml
git_backed: true | false
remote: gitea | github | none
branch_required: true | false
access: readwrite | readonly
inherit: true | false
owning_agent: <agent-name> | shared
pre_edit_skill: <skill-name>  # optional
notes: "<freeform>"           # optional
```

| Category | Paths covered |
|----------|--------------|
| gitea repos | `~/repos/gitea/` (root), `agent-platform/`, `agent-platform-agents/`, `agent-platform-manual/`, `agent-platform-operator/`, `agent-platform-skills/`, `agent-templates/`, `forge-configs/`, `host-forge/`, `host-forge-scripts/`, `host-forge-scripts/scripts/`, `host-forge-build-reports/` |
| personal repos | `~/repos/personal/` |
| Docker / appdata | `~/docker/`, `/opt/appdata/` |
| Claude dirs | `~/.claude/`, `~/.claude/memory/`, `~/.claude/memory/agents/developer/`, `~/.claude/memory/agents/research/`, `~/.claude/memory/agents/security/`, `~/.claude/memory/agents/sysadmin/`, `~/.claude/memory/agents/writer/`, `~/.claude/memory/shared/`, `~/.claude/comms/` |
| NFS | `/mnt/atlas/` (readonly) |

Existing markers at `~/docker/` and `/opt/appdata/` updated from `owning_agent: helm-build` to `sysadmin`.

### Agent manifest workspace_access sections

All 5 agent manifests (`developer`, `research`, `security`, `sysadmin`, `writer`) extended with `workspace_access` sections in `~/repos/gitea/host-forge-scripts/manifests/`. Each section declares only the directories that agent legitimately writes — cross-referenced against CLAUDE.md memory sections and tool surfaces.

### agent-workspace-scan.py (PM2 cron)

Python scanner at `~/repos/gitea/host-forge-scripts/scripts/agent-workspace-scan.py` (deployed via hard link to `~/scripts/`). Runs hourly via PM2 cron.

**Four responsibilities:**

| Phase | Function |
|-------|----------|
| 2a — Manifest generation | Walks all 25 roots, regenerates `agent-access-map.md` in `~/repos/gitea/agent-platform/` |
| 2b — Drift detection | Auto-heals untracked/modified markers (git-backed paths); escalates blind spots, field errors, and access permission conflicts to Matrix `#sysadmin` |
| 2c — Event emission | Writes structured JSON to `~/.claude/logs/agent-workspace-scan.log`; emits to agent-bus with CIA class taxonomy |
| 2d — Rogue agent detection | Tracks edit volume per agent via git log; `ROGUE_AGENT_EDIT_THRESHOLD=0` (disabled, pending 1–2 week baseline calibration) |

**Phase 2e — Source domain check:** SQL cross-reference against `.metadata.db` detects notes in `agents/<name>/` whose `source` field doesn't match the owning agent. Anomalies moved to `~/.claude/memory/.quarantine/<date>/` with 700 permissions; `workspace.alert` emitted with `cia_class: confidentiality`.

**Phase 2f — Config tamper detection:** Checksums tracked config files in `/opt/appdata` against the `forge-configs` repo. Alerts via Matrix `#sysadmin` and `workspace.alert` event on any divergence, indicating an out-of-band edit that bypassed the repo workflow.

### forge-configs repo

New Gitea repo (`host-forge/forge-configs`) tracking non-secret config files. See [forge-configs component doc](../components/forge-configs.md).

### agent-workspace-check skill

Skill ported from claudebox to `~/repos/gitea/agent-platform-skills/agent-workspace-check/SKILL.md`. Pre-edit hook: resolves workspace config for target path (walks up, caches per session), enforces branching rules, blocks edits on `access: readonly` paths, alerts on inheritance gaps.

### agent-access-map.md

`~/repos/gitea/agent-platform/agent-access-map.md` committed and regenerated hourly by the scanner. Contains a table of all workspace roots with ownership, access mode, git backing, and recent self-heals.

---

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| 25 roots instead of 19 (plan) | M3 audit finding revealed 6 uncovered gitea sub-repos; added markers and WORKSPACE_ROOTS entries as part of audit triage |
| forge-configs created as new repo | Config files extracted from ad-hoc `/opt/appdata` location into version-controlled repo; Vault KV for secrets, git for non-secret config |
| Matrix replaces ntfy | Forge uses Matrix (`send-matrix.sh`) — no ntfy service running |
| agent-bus replaces InfluxDB | Forge uses agent-bus for event emission; no local InfluxDB |
| `ROGUE_AGENT_EDIT_THRESHOLD=0` | No baseline yet; detection disabled pending 1–2 week observation window |
| Quarantine dir at `700` | Memory quarantine may contain sensitive note content; restricted to ted only |
| `pre_edit_skill: git-config-tracking` stubs | Skill noted in markers but stubbed; full implementation in follow-on work |

---

## Security Audit

**Outcome:** PASS — 3 medium, 3 low, 3 info. 7 resolved, 2 accepted.

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | `forge-configs-deploy.sh` heredoc injection via Vault KV data | `deploy_env()` switched to `printf '%s' "\$kv_data" \| python3 -` with quoted `<<'PYEOF'` (commit `bd1f90e`) |
| M2 | Medium | `source_domain_check()`: note path not canonicalized before quarantine move | Added `Path.resolve()` + memory root bounds check (commit `f2a166b`) |
| M3 | Medium | Scanner blind spot: 6 gitea sub-repos uncovered under `inherit: false` parent | Markers written to all 6 repos; WORKSPACE_ROOTS expanded 19 → 25 (commit `cc43dc4`) |
| L1 | Low | Quarantine dest filename collision on same-filename notes | Prefixed with `{declared_source}_{expected_owner}_` (commit `b29587b`) |
| L2 | Low | `agent-workspace-status.json` created at 644 | `write_status_file()` uses `os.open(..., 0o600)` (commit `b29587b`) |
| L3 | Low | Vault token visible in `curl` CLI args | Vault token passed via `mktemp --config` file (commit `245a64b`) |
| I1 | Info | `.metadata.db` world-readable | `chmod 600 ~/.claude/memory/.metadata.db` applied |
| I2 | Info | Rogue agent detection disabled (`THRESHOLD=0`) | Accepted — calibration pending; `SECURITY[accepted]` comment in code |
| I3 | Info | All agents have write access to `~/.claude/memory/shared/` | Accepted design — carries forward to `memory-eval-poisoning-2026-06` scope |

---

## Related Docs

- [forge-configs component](../components/forge-configs.md) — config tracking repo and deploy script
- [AGENT_WORKSPACE.md schema](../../AGENT_WORKSPACE.md) — marker file schema reference
- Audit report: `host-forge/build-reports/agent-workspace-forge-2026-06/audit.md`
- Build plan: `~/.claude/comms/artifacts/build-plans/archive/agent-workspace-forge-2026-06/plan.md`
- Prerequisite for: `memory-eval-poisoning-2026-06`
