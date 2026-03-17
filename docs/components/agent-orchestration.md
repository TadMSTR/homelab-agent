# Agent Orchestration

The inter-agent handoff system described in [inter-agent-communication.md](inter-agent-communication.md) handles direct agent-to-agent work: a research agent writes a build plan, a building agent picks it up. That pattern is simple and works well for a known source and a known target.

Once you have several agents that can all hand work to each other, you need something in the middle. Agent orchestration adds a structured task queue, a dispatcher that routes and gates tasks automatically, and a CLI for approving anything that needs a human look before it proceeds. The handoff pattern doesn't go away — it's still how build plans and security audit requests flow. The task queue is the layer on top that adds lifecycle tracking, approval gates, and routing for cases where the source agent doesn't know or care who handles the work.

## How It Fits In

This is a Layer 3 concern. It sits entirely in the filesystem — no services, no message bus, no ports. The components are:

- `~/.claude/task-queue/` — YAML task files, one per task, plus an `archive/` subdirectory
- `~/.claude/agent-manifests/` — one manifest per agent, describing its capabilities and risk thresholds
- `~/scripts/task-dispatcher.py` — PM2 cron, runs every 2 minutes, processes submitted tasks
- `~/scripts/task-approve.py` — CLI installed to `~/bin/task-approve` for Ted's approval actions
- `~/.claude/hooks/inject-task-queue.sh` — SessionStart hook that surfaces pending tasks to agents

The dispatcher handles the mechanical work: routing submitted tasks, applying approval gates, alerting on stale items, and archiving completed ones. Agents interact with the queue by writing task files (to submit work) and reading their own task files at session start (to pick up approved work). Ted interacts via `task-approve`.

## Prerequisites

- Layer 3 baseline: Claude Code CLI with per-project CLAUDE.md files
- PM2 for running the dispatcher as a cron job
- ntfy for approval and stale-task push notifications
- Agent manifests written for each agent you want to route tasks to
- The inter-agent handoff pattern set up if you want the full bidirectional workflow — though the task queue works standalone for unidirectional dispatch

## Agent Manifests

Manifests are the registry. Each one describes what an agent can do, where it lives, what risk level it's allowed to auto-approve, and whether it accepts inbound tasks from the queue.

```yaml
# ~/.claude/agent-manifests/claudebox.yml
name: claudebox
project_path: /home/ted/.claude/projects/claudebox/
type: claude-code                       # claude-code or pm2-cron
capabilities:
  - build
  - deploy
  - fix
scope:
  hosts: [claudebox]
max_auto_risk: low                      # Tasks at this risk level and below are auto-approved
accepts_inbound: true                   # Whether this agent accepts tasks from the queue
description: "Day-to-day claudebox operations — Docker stacks, PM2 services, Claude Code engine"

workspace_access:
  - path: ~/scripts/
    access: readwrite
    branch_required: false
  - path: ~/docker/
    access: readwrite
    branch_required: false
  - path: /opt/appdata/
    access: readwrite
    branch_required: false
  - path: ~/repos/
    access: readwrite
    branch_required: true
  - path: ~/.claude/
    access: readwrite
    branch_required: false
  - path: /mnt/atlas/
    access: readonly

interaction_permissions:
  auto_approved:
    - research                          # Tasks from research agent dispatch without operator approval
    - doc-health                        # Tasks from doc-health dispatch without operator approval
  needs_approval:
    - security-agent                    # Tasks from security agent require operator approval
```

The `capabilities` list is free-form, but you need consistent names across manifests and task files — the dispatcher matches `task_type` in the task file against `capabilities` in the manifest for auto-routing. The `max_auto_risk` field is the key safety control: a `low` risk task goes through automatically, a `medium` or `high` task sits at `pending-approval` until you run `task-approve <id>`.

`workspace_access` declares the filesystem paths this agent needs and at what access level. This feeds the two-party permission model in the Agent Workspace Protocol — the agent's manifest declares intent, and the `AGENT_WORKSPACE.md` marker at each path declares what's allowed. The stricter of the two wins. The hourly workspace scan (`agent-workspace-scan`) cross-references these entries against the actual markers and flags any access level disagreements. See [agent-workspace-scan](agent-workspace-scan.md) and [agent-workspace-check](agent-workspace-check.md).

`interaction_permissions` controls dispatch trust by source agent rather than just by risk level. Agents in `auto_approved` have their submitted tasks fast-tracked through the approval gate — useful for agents you trust to submit well-scoped work (research, doc-health). Agents in `needs_approval` require operator review regardless of the task's declared risk level — useful for agents with broad execution authority (security-agent). This is separate from the `max_auto_risk` check: both gates apply, and either can hold a task at `pending-approval`.

A `type: pm2-cron` agent (like doc-health) can appear in manifests but doesn't accept inbound tasks — it runs on schedule, doesn't pick up queue items on session start. Set `accepts_inbound: false`.

## Task File Schema

Tasks are YAML files in `~/.claude/task-queue/`. The dispatcher processes any file with `status: submitted` on its next run.

```yaml
id: a7f3d2c1-...                        # UUID, generated by the submitting agent
created: "2026-03-15T14:00:00+00:00"
source_agent: research
target_agent: claudebox                 # Explicit agent name, or "auto" to resolve via manifests
task_type: build
risk_level: low                         # low | medium | high
requires_approval: false                # Override approval logic if set; omit to use manifest defaults
status: submitted
summary: "Deploy qmd stack update per plan"
ttl_days: 30                            # Days until terminal tasks are archived

payload:
  description: >
    Apply the qmd stack update from the build plan. Update the compose file,
    pull the new image, restart the container, verify search is healthy.
  context_refs:
    - ~/.claude/projects/research/build-plans/qmd-update/plan.md
  priority: normal

result:
  output: ""                            # Populated by the target agent on completion
  completed_by: ""
  completed_at: ""

history:
  - timestamp: "2026-03-15T14:00:00+00:00"
    status: submitted
    actor: research
    note: "Build plan complete, handing off to claudebox"
```

The `history` array is append-only — every status transition gets an entry. The dispatcher writes entries when routing and approving; the target agent writes when it claims the task (`working`) and completes it (`completed` or `failed`).

## Status Lifecycle

```
submitted → [pending-approval] → approved → working → completed
                                                ↕
                                        input-required
                                             ↓
                                           failed
```

The `pending-approval` stop is determined by comparing `risk_level` against the target agent's `max_auto_risk`. If a `medium` risk task goes to an agent whose manifest says `max_auto_risk: low`, it holds. You get an ntfy notification with the approval command. If the task's `requires_approval: false` is set explicitly, the check is skipped regardless of risk level — useful for tasks you're scheduling programmatically and have already reviewed.

`input-required` is for tasks that are partially complete but need a human answer before proceeding. The target agent sets this status and adds context in the history entry or result field. The inject hook surfaces `input-required` tasks at session start the same way it surfaces `approved` ones.

`failed` gets written either by the dispatcher (no manifest found for `target_agent: auto`, parse error) or by the target agent on an unrecoverable error. The failed entry in `history` should include why it failed and how far it got.

## The Dispatcher

`task-dispatcher.py` runs as a PM2 cron job every two minutes. Three phases per run:

1. **Process submitted tasks.** For each `status: submitted` file: resolve auto-routing if `target_agent: auto`, apply the approval gate, write the new status and history entry atomically.

2. **Alert on stale approved tasks.** Any task stuck at `approved` for more than 24 hours gets an ntfy notification. This catches the case where an agent was never opened after a task was approved, or the session-start hook didn't surface it for some reason.

3. **Archive expired terminal tasks.** Tasks with `status: completed` or `failed` move to `archive/` when they exceed `ttl_days` from their creation date. The queue stays clean without losing the historical record.

All file writes use atomic rename (write to `.tmp`, rename to final) to avoid half-written files being picked up mid-run.

PM2 config:

```javascript
{
  name: "task-dispatcher",
  script: "/home/ted/scripts/task-dispatcher.py",
  interpreter: "python3",
  cron_restart: "*/2 * * * *",
  watch: false,
  autorestart: false,
}
```

## The SessionStart Hook

`inject-task-queue.sh` is a Claude Code SessionStart hook. When an agent session starts, it scans `~/.claude/task-queue/` for files with `status: approved` or `status: input-required` and injects them as `additionalContext`.

The injected block looks like:

```
# Orchestration Task Queue — 2 tasks pending

Review the tasks below. Act on those where `target` matches your agent name.
When starting work: set status=working (atomic write). On completion: status=completed with result.

- [APPROVED] Deploy qmd stack update per plan
  target: claudebox | type: build | risk: low | source: research | priority: normal
  id: a7f3d2c1-...
  description: Apply the qmd stack update from the build plan...
  context_refs: ~/.claude/projects/research/build-plans/qmd-update/plan.md
```

Agents self-filter by `target` — the hook injects everything, each agent decides what's theirs. This is intentional: an agent can see that other agents have pending work, which is occasionally useful context even if the task isn't for them.

The hook is registered in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "type": "command", "command": "bash /home/ted/.claude/hooks/inject-task-queue.sh", "timeout": 10 }
    ]
  }
}
```

## The task-approve CLI

```
task-approve list                           # show pending-approval tasks
task-approve status                         # show all tasks and their states
task-approve <task-id>                      # approve a task
task-approve <task-id> --reject "reason"    # reject with note
```

The `list` output includes the full approval and rejection commands so you can copy-paste from the notification. Task IDs can be partial — `task-approve a7f3d2` matches the full UUID.

ntfy notifications for `pending-approval` tasks include the approval command inline in the message body, so you can act from your phone without opening a terminal.

## Integration Points

**Submitting a task from another agent.** A research agent completing a build plan can write a task file directly to `~/.claude/task-queue/` with `status: submitted`. The dispatcher picks it up on its next run (within 2 minutes) and handles routing and approval. Alternatively, a building agent can submit a security audit request this way instead of writing directly to the security queue — both patterns coexist.

**ntfy.** Two notification types: `pending-approval` (fire immediately when a task is gated) and stale approved (fire every 6-hour run while a task remains unclaimed). The dispatcher uses ntfy directly via curl; the same ntfy topic used by the resource monitor and other alerts.

**Atomicity.** All dispatchers and agents use atomic write (tmp + rename). This matters when the dispatcher and an agent session are both active — without it, a partially-written task file can corrupt the queue state or lose history entries.

## Gotchas

**Auto-routing requires consistent capability names.** If a research agent submits `task_type: build` but the manifest says `capabilities: [deploy, fix]`, auto-routing fails and the task goes to `failed` immediately. Pick a small vocabulary for `task_type` and stick to it across all agents. The current set is `build`, `deploy`, `fix`, `research`, `review`, `audit`, `notify`.

**The session-start hook injects everything, not just your tasks.** This is the intended behavior — agents see the full queue. But it means a busy queue with 10+ tasks creates a lot of injected context. Keep `ttl_days` reasonable and let the archiver do its job. If the queue stays long, that's a signal to run `task-approve status` and clear out stale items.

**`requires_approval: false` bypasses the manifest risk check.** This is useful for programmatic submissions you've already reviewed, but it means a high-risk task can slip through if an agent sets it. Keep it omitted unless you have a specific reason to override.

**The dispatcher doesn't retry failed routing.** If a task hits `status: failed` because no manifest matched `target_agent: auto`, fix the manifest and resubmit a new task. The failed file stays in the queue until archiving. Don't edit the status field back to `submitted` — the dispatcher won't re-process it reliably if history is inconsistent.

**Stale alert fires every 2-minute run after 24h, not once.** The Phase 2 stale check doesn't track whether it already notified. A task approved on Monday that nobody picks up will generate a notification on every dispatcher run from Tuesday onward. Pick it up or reject it.

## Standalone Value

The core of this — task files, a manifest registry, a dispatcher, and a CLI — works without the rest of the homelab-agent stack. If you have Claude Code projects that hand work to each other and want approval gates without building a full workflow system, this is the minimum:

1. Write manifests for your agents
2. Write a task file with `status: submitted` when you want to route work
3. Run `task-dispatcher.py` on a schedule (PM2 cron or system cron)
4. Add the session-start hook to surface approved tasks

The SessionStart hook and the inter-agent handoff pattern ([inter-agent-communication.md](inter-agent-communication.md)) are complementary, not competing. The handoff pattern handles direct agent-to-agent queues (build plans, security audit requests) with their own directory layouts and metadata formats. The task queue handles anything that needs centralized routing, approval gating, or lifecycle tracking across multiple agents. Use both — they solve different problems.

---

## Related Docs

- [Inter-Agent Communication](inter-agent-communication.md) — the file-based handoff pattern this system builds on
- [security-agent](security-agent.md) — the first agent to use bidirectional task routing
- [memory-sync](memory-sync.md) — background agent that will eventually submit tasks rather than run standalone
- [Architecture](../architecture.md) — full data flow diagrams for the Layer 3 engine
