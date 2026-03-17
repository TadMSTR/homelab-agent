# Agent Workspace Check

Agent workspace check is a pre-edit resolver skill that runs before any agent touches a file outside its active project directory. It walks up the directory tree from the target path to find the nearest `AGENT_WORKSPACE.md` marker, reads the workspace configuration declared there, and enforces it before the edit proceeds. If no marker covers the path, the agent halts and notifies the operator.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) as a prerequisite gate for the `git-config-tracking` skill. Together they form the pre-edit half of the Agent Workspace Protocol: workspace-check verifies authorization, git-config-tracking handles version tracking.

## Why a Pre-Edit Check

Multiple agents operate on claudebox with overlapping filesystem access. Without a shared permission layer, each agent relies on its own judgment about what it's allowed to touch. This works until it doesn't — a misconfigured agent, a mistaken path, or a task dispatched with too broad a scope can produce edits that shouldn't have happened.

The workspace check adds an independent enforcement layer that sits between the agent and the filesystem. The agent's manifest declares what it claims to need; the `AGENT_WORKSPACE.md` in the target directory declares what the directory allows. Neither alone is sufficient — the stricter of the two wins, every time.

## Resolution Algorithm

1. **Start at the target file's directory.** Walk up toward the filesystem root.

2. **At each directory:** check for `AGENT_WORKSPACE.md`. If found, load the YAML front matter and apply the rules below. If the file has `inherit: true`, it covers all subdirectories — no need to keep walking.

3. **If nothing is found:** halt, send an ntfy alert, and inform the user:
   ```
   No workspace marker found for <path>. Halting edit — operator notified.
   ```

Once a workspace config is resolved for a path root, it's cached for the remainder of the session — repeated edits under the same root don't require repeated filesystem walks.

## AGENT_WORKSPACE.md Schema

Each marker file uses YAML front matter with these fields:

```yaml
---
git_backed: true          # Is this directory tracked in a git repo?
remote: gitea             # Remote type: gitea | github | none
branch_required: false    # Must edits happen on a non-main branch?
access: readwrite         # readwrite | readonly
inherit: true             # Does this marker cover all subdirectories?
owning_agent: claudebox   # Which agent is responsible for this workspace
pre_edit_skill: git-config-tracking   # Skill to invoke before edits (optional)
notes: "Human context."   # Free-form notes for operators
---
```

The seven workspace roots and their key settings:

| Path | access | git_backed | branch_required | pre_edit_skill |
|------|--------|-----------|-----------------|----------------|
| `~/scripts/` | readwrite | true (Gitea) | false | git-config-tracking |
| `~/docker/` | readwrite | true (Gitea) | false | git-config-tracking |
| `/opt/appdata/` | readwrite | true (Gitea) | false | git-config-tracking |
| `~/repos/` | readwrite | true (GitHub) | true | git-config-tracking |
| `~/.claude/` | readwrite | false | false | _(none)_ |
| `~/bin/` | readwrite | false | false | _(none)_ |
| `/mnt/atlas/` | readonly | false | — | — |

## Enforcement Rules

**`access: readonly`** — Refuse the edit entirely. Output a clear refusal and stop. If this seems wrong, the operator needs to update the workspace file.

**`access: readwrite`** — Proceed to the next checks.

**`git_backed: true`** — Verify `git-config-tracking` is active. If not, invoke it before proceeding. This ensures a pre-edit commit captures the baseline state and a post-edit commit records the change.

**`branch_required: true`** — Confirm the repo is on a non-main branch before editing:
```bash
git -C <repo-root> branch --show-current
```
If on `main` or `master`, halt and ask the user to create or switch to a feature branch. Documentation-only repos (`claude-prime-directive`, `homelab-agent`) are exempt — they use direct-to-main commits per project convention.

**`pre_edit_skill: <skill-name>`** — After resolving workspace config, invoke the named skill before proceeding. The primary case is `git-config-tracking`. This ensures the pre-edit/post-edit commit workflow runs.

**No marker found** — Halt and send ntfy:
```
Title: [agent-workspace] Missing marker: <path>
Body: No AGENT_WORKSPACE.md covers <path>. Operator must create one before edits can proceed.
```

## Two-Party Permission Model

If the current agent's manifest (`~/.claude/agent-manifests/<agent>.yml`) is available, the resolved workspace access is cross-checked against what the manifest claims:

| Manifest claims | Workspace declares | Result |
|----------------|-------------------|--------|
| readwrite | readwrite | Proceed |
| readwrite | readonly | **Block — log CIA:confidentiality conflict** |
| readonly | readonly | Proceed (read-only confirmed) |
| readonly | readwrite | Proceed with read-only intent |

A confidentiality conflict means the agent has overclaimed its permissions. This is logged, the edit is halted, and a high-priority ntfy alert is sent. The conflict is also picked up by the hourly [agent-workspace-scan](agent-workspace-scan.md) and recorded in the operator manifest.

The model is "two-party" because both parties must agree before an edit can happen: the agent's manifest and the workspace marker. Either party can block. This separation means the permission layer holds even if one side is misconfigured.

## Integration with git-config-tracking

This skill acts as a prerequisite gate for `git-config-tracking`. When git-config-tracking is triggered:

1. `agent-workspace-check` runs first.
2. If access is confirmed (`readwrite`) and `git_backed: true`: proceed with git-config-tracking's pre-edit/post-edit commit workflow.
3. If access is `readonly` or no marker covers the path: halt before git-config-tracking runs any git commands.

This ensures no git operations happen on paths the agent isn't authorized to touch.

## When This Skill Triggers

Run before editing files in:
- `~/scripts/` — git-config-tracking paths
- `~/docker/` — git-config-tracking paths
- `/opt/appdata/` — git-config-tracking paths
- `~/repos/` — any personal or work repos
- `~/.claude/` — memory, skills, agent manifests, task queue
- `~/bin/` — symlink directory
- Any path outside the current active project workspace

When `git-config-tracking` is triggered for any reason, this skill runs first.

## Prerequisites

- `AGENT_WORKSPACE.md` files present at each workspace root (placed during the workspace protocol build, maintained by [agent-workspace-scan](agent-workspace-scan.md))
- Agent manifests at `~/.claude/agent-manifests/<agent>.yml` for the two-party cross-check (optional but recommended)
- ntfy configured for operator notifications

## Gotchas and Lessons Learned

**The skill caches resolved configs per session.** Once a workspace root is resolved, the config is reused for all subsequent edits under that root. If you manually edit an `AGENT_WORKSPACE.md` mid-session to change access levels, start a fresh session for the new config to take effect.

**`/mnt/atlas/` is hardcoded readonly.** The NFS mount has no `AGENT_WORKSPACE.md` — writes aren't possible there. The skill handles `/mnt/atlas/` as a special case: any path under it resolves to `access: readonly` without needing a marker file.

**Documentation repos are exempt from `branch_required`.** `claude-prime-directive` and `homelab-agent` both use direct-to-main commits as a documented project convention. The workspace check respects this — `branch_required` in their workspace markers is `false`.

**Missing marker is a hard stop, not a warning.** The design is intentional: an uncovered path is more dangerous than a blocked edit. If a new directory is created that agents need to edit, the marker must be created first. The [agent-workspace-scan](agent-workspace-scan.md) will detect and alert on newly uncovered paths.

**Readonly conflicts are silent by design.** An agent claiming `readonly` on a `readwrite` path is fine — it's being more restrictive than required. Only overclaiming (readwrite on readonly) triggers an alert.

## Standalone Value

The `AGENT_WORKSPACE.md` marker pattern is lightweight and portable. If you're running multiple Claude Code agents with overlapping filesystem access, dropping a marker file at each directory root gives you a machine-readable permission declaration that any skill or agent can check before acting. The two-party model — agent manifest plus workspace marker — is the part that's hard to replicate with just a CLAUDE.md file: it provides an independent check that persists even when the agent's instructions change.

## Related Docs

- [agent-workspace-scan](agent-workspace-scan.md) — maintains the markers this skill reads, emits events, cross-references manifests hourly
- [agent-orchestration](agent-orchestration.md) — agent manifests and task dispatch
- [git-config-tracking skill](../../skills/git-config-tracking/) — the downstream skill this gates
