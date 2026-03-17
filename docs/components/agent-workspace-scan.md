# Agent Workspace Scan

Agent workspace scan is the maintenance backbone of the Agent Workspace Protocol. A Python script runs hourly via PM2 cron (`agent-workspace-scan`) and does three things in a single pass: validates that every known workspace root has a properly-formed `AGENT_WORKSPACE.md` marker, auto-heals drift by committing modified or untracked markers in git-backed paths, and emits structured events to InfluxDB and Loki so you can see the health of the permission layer over time.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) alongside the other background agents. The scan is what keeps the workspace permission layer alive and auditable — without it, marker files would go stale or missing without anyone noticing.

## Why a Scan Script

The agent workspace permission system is only useful if the markers it enforces are actually present, valid, and current. An agent creating a new workspace marker, or a manual edit to an existing one, can easily go untracked. The manifest of what agents are allowed to touch (`agent-access-map.md`) would also go stale the moment any marker changed.

The scan script removes the human maintenance burden. It's the difference between a permission system that requires constant upkeep and one that self-maintains.

## Triple Duty

**Duty 1: Validate and heal workspace markers.**

For each of the seven workspace roots, the scan checks:

- Is `AGENT_WORKSPACE.md` present?
- Can it be parsed (valid YAML front matter)?
- Does it contain all required fields (`git_backed`, `remote`, `branch_required`, `access`, `inherit`, `owning_agent`)?
- For git-backed paths: is the file tracked and committed?

Recoverable issues are auto-healed silently. Untracked or modified markers in git-backed repos are staged, committed, and pushed. Issues that require operator attention — a missing marker with no inheriting parent, a parse failure, a `git_backed: true` path that isn't actually a git repo — are escalated via ntfy and recorded as alerts.

**Duty 2: Cross-reference agent manifests.**

Each agent has a manifest at `~/.claude/agent-manifests/<agent>.yml` that declares its `workspace_access`: a list of paths it claims to need and at what access level. The scan reads these manifests and cross-references them against the actual workspace markers.

Two classes of disagreement are flagged:

- **CIA confidentiality conflict:** The agent's manifest claims `readwrite` on a path where the `AGENT_WORKSPACE.md` says `readonly`. The agent has overclaimed its permissions.
- **Blind spot:** The agent references a path that has no `AGENT_WORKSPACE.md` coverage at all. The path isn't covered by any marker or inheriting parent — the agent could operate there with no permission layer in place.

Both are emitted as events to InfluxDB and Loki, and the confidentiality conflicts trigger an ntfy alert.

**Duty 3: Rogue agent detection (currently calibrating).**

The script contains an edit-volume threshold check: if a single agent commits across too many paths in the scan window, it's flagged as potentially rogue. When triggered, it writes a lockdown snapshot log, dispatches a `risk:critical` task to the security agent via the task queue, and sends an urgent ntfy notification.

The threshold is currently set to `0` (disabled). Baseline edit volumes need a week or two of observation before meaningful thresholds can be set. The infrastructure is wired and ready — only the calibration number is missing.

## Workspace Roots

Seven roots are scanned on every run:

| Root | git_backed | Notes |
|------|-----------|-------|
| `~/repos/` | false (root itself) | Subdirectory repos are individually git-backed |
| `~/scripts/` | true (Gitea) | Pre-edit and post-edit commits required |
| `~/docker/` | true (Gitea) | Compose files and stack configs |
| `~/.claude/` | false | Memory, manifests, task queue — file existence and field check only |
| `~/bin/` | false | Symlink directory |
| `/opt/appdata/` | true (Gitea) | Docker appdata |
| `/mnt/atlas/` | false (ro NFS) | Write-protected — hardcoded `access: readonly`, no marker file possible |

Non-git paths (`~/repos/` root, `~/.claude/`, `~/bin/`, `/mnt/atlas/`) are validated for file presence and field completeness but no git operations are attempted.

## How Markers Are Validated

The front matter of each `AGENT_WORKSPACE.md` is YAML between `---` delimiters:

```yaml
---
git_backed: true
remote: gitea
branch_required: false
access: readwrite
inherit: true
owning_agent: claudebox
pre_edit_skill: git-config-tracking
notes: "Human-readable context for this workspace root."
---
```

Required fields: `git_backed`, `remote`, `branch_required`, `access`, `inherit`, `owning_agent`. If any are missing, the scan emits an `alert_invalid` event and sends an ntfy notification. The marker is recorded in the manifest with `status: invalid` so it's visible in the operator dashboard.

The `inherit: true` field signals that this marker covers all subdirectories — subdirs don't need their own files. `inherit: false` means each subdirectory must have its own marker. A directory not covered by any marker or inheriting parent is a blocking gap — agents will halt rather than edit there.

## Event Emission

Every meaningful scan event — heals, alerts, manifest regeneration — is emitted in two ways:

**InfluxDB** (`claudebox_self_healing_events` measurement, `claudebox-agent` bucket):
```
Tags: system, event_type, location, agent, severity, cia_class
Fields: detail (string)
```

CIA triad tags (`cia_class`) classify the nature of each event:
- `none` — benign heal, no security implication
- `availability` — missing marker means an agent might be blocked
- `integrity` — parse failure or git_backed mismatch
- `confidentiality` — agent claims more access than the workspace declares

**Loki** (`/var/log/claudebox/agent-workspace.log`, `{job="self-healing"}`): same events as structured JSON log lines, picked up by Alloy and shipped to local Loki. See [grafana-observability](grafana-observability.md) for the log shipping setup.

## Manifest Regeneration

After each scan, the script rewrites `infrastructure/agent-access-map.md` in the prime-directive repo with the current state of all workspace roots and recent heal/alert activity. This file is the operator's single-pane view of the workspace permission layer. It's committed and pushed automatically — never edit it by hand.

## PM2 Service

The scan runs as PM2 cron job `agent-workspace-scan`, scheduled hourly. Stopped status after a run is normal for scheduled PM2 jobs — the process exits when the scan completes and PM2 records the final state.

The wrapper script `~/scripts/run-agent-workspace-scan.sh` sources `~/docker/grafana/.env` before invoking the Python script, which is how the `INFLUXDB_ADMIN_TOKEN` gets injected without hardcoding credentials in the PM2 ecosystem config.

```bash
# How the wrapper injects credentials
set -a
source ~/docker/grafana/.env
set +a
exec python3 ~/scripts/agent-workspace-scan.py "$@"
```

## Status File

After each run, the scan writes `~/.claude/agent-workspace-status.json` with the current health summary:

```json
{
  "status": "clean",        // clean | healing | needs_operator
  "last_scan": "...",
  "pending_alerts": [],
  "recent_heals": 0
}
```

This file is designed for a future claudebox-panel widget showing workspace integrity status. The three states map to green / amber / red.

## Prerequisites

- Python 3 with `pyyaml` installed
- PM2 for cron scheduling
- `AGENT_WORKSPACE.md` files created at each workspace root (placed during the initial build)
- InfluxDB running locally with the `claudebox-agent` bucket — see [grafana-claudebox](grafana-claudebox.md)
- `/var/log/claudebox/` directory writable by the running user
- Gitea SSH access for git push from auto-heal commits on `~/scripts/`, `~/docker/`, `/opt/appdata/`

## Gotchas and Lessons Learned

**Stopped PM2 status is normal.** The scan exits on completion. PM2 shows `stopped` after a cron job runs — that's expected. Check the logs (`pm2 logs agent-workspace-scan`) rather than status if you want to see what happened.

**Rogue agent detection needs calibration before enabling.** `ROGUE_AGENT_EDIT_THRESHOLD = 0` disables the check entirely. Setting any non-zero value activates it. Watch the InfluxDB data for a week or two to understand normal commit volumes before choosing a threshold — otherwise the first agent to do a large batch update will trigger a false lockdown.

**`/mnt/atlas/` has no marker file — this is intentional.** The NFS mount is read-only and the script has no write access there. The scan handles it with a hardcoded `access: readonly` entry rather than requiring a marker that can't exist. Agents that try to write to `/mnt/atlas/` paths will be blocked.

**Push failures after heal commits aren't fatal.** If Gitea is temporarily unreachable, the auto-heal commit still lands locally and the scan continues. The next run will push the commit. A push failure is logged as a warning, not an error, so it won't trigger a false alert.

**Manifest commit "nothing to commit" is normal.** If no workspace roots changed since the last scan, the manifest content will be identical (same fields, different timestamp). The script detects this and skips the commit rather than spamming the git log.

## Integration Points

**agent-workspace-check skill:** The check skill is the enforcement side of this protocol — it runs before any agent edit. The scan script is the maintenance side. The scan keeps markers valid; the check skill enforces them. See [agent-workspace-check](agent-workspace-check.md).

**InfluxDB:** Events land in the `claudebox_self_healing_events` measurement. Feed this into a Grafana panel alongside memory-pipeline and task-dispatcher events for a unified self-healing system view.

**Loki:** Log lines tagged `{job="self-healing"}` appear alongside other self-healing agent logs in the local Loki instance. Query `{job="self-healing", filename=~".*agent-workspace.*"}` to filter to just this component.

**agent-access-map.md:** The manifest file in the prime-directive repo is this script's primary human-readable output. It regenerates on every run. Reference it when auditing what agents are allowed where.

**Security agent:** Rogue agent detection dispatches directly to the security agent via the task queue using `bypass_approval: true`. When a lockdown fires, the security agent picks up the task on its next dispatch cycle without waiting for manual approval.

## Standalone Value

The workspace protocol pattern is worth reusing for any multi-agent setup where several agents need to edit overlapping directories. The `AGENT_WORKSPACE.md` marker approach is simple to implement — a YAML front matter file at each root — and the scan script is self-contained Python. The two-party permission model (agent manifest declares intent, workspace marker declares allowed access, stricter wins) adds an independent check that doesn't rely on the agent being correctly configured.

## Related Docs

- [agent-workspace-check](agent-workspace-check.md) — the pre-edit enforcement skill this scan maintains markers for
- [agent-orchestration](agent-orchestration.md) — task dispatcher and agent manifest schema
- [grafana-observability](grafana-observability.md) — local Loki and InfluxDB event pipeline
- [memory-sync](memory-sync.md) — companion self-healing agent with similar PM2 cron pattern
