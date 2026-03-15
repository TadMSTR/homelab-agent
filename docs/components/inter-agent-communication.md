# Inter-Agent Communication

Agents in this system don't share a runtime or a message bus. Each one is a separate Claude Code session with its own CLAUDE.md context, scoped memory, and tooling. Communication happens entirely through the filesystem — structured metadata files in known directories that agents discover on session start.

This pattern emerged from the build plan workflow (research agents handing off to implementing agents) and was extended bidirectionally when the security audit workflow added a return path. The mechanics are the same in both directions.

## How It Fits In

Inter-agent communication is a Layer 3 concern. It sits on top of the multi-agent Claude Code engine and doesn't touch the Docker service stack or host tooling. The only infrastructure it requires is a shared filesystem — which the agents already have.

The security audit workflow is the first bidirectional use of this pattern. A building agent writes outbound to the security queue; the security agent writes inbound action plans back. Future agents (diagnostics, dep-updates) reuse the same mechanics.

## Prerequisites

- Claude Code CLI with per-project CLAUDE.md files (Layer 3 baseline)
- A shared filesystem accessible to all agent chats (standard on a single host)
- The agent capability index (`agents.md` in the context repo) for routing decisions

## The Handoff Pattern

Every inter-agent handoff follows the same structure: a queue directory that the source agent writes to, a metadata file the target agent reads on session start, and a status field both agents update as work progresses.

### Queue Directory Layout

```
~/.claude/projects/security/
  audit-queue/
    <build-name>/
      request.md          ← source agent writes this
  action-plans/
    <build-name>/
      plan.md             ← security agent writes this
      handoff.md          ← for non-security targets, routes back to building agent
```

For build plan handoffs (research → implementing agents):

```
~/.claude/projects/research/
  build-plans/
    <plan-name>/
      plan.md
      handoff.md          ← target agent, status, brief
```

The directory is the container. The metadata file (`request.md`, `handoff.md`) is the signal. The target agent scans for them on session start.

### Metadata File Format

Every handoff file follows the same loose schema at the top:

```markdown
# <build-or-plan-name>

status: pending
target-agent: claudebox | dev | homelab-ops | security
source-agent: claudebox | dev | homelab-ops | research
completed: YYYY-MM-DD

## Brief
One paragraph summary of what this handoff contains and what the target agent should do.

## [Content sections vary by handoff type]
```

For security audit requests, the request file includes what was built, which repos changed, what ports are exposed, and what auth layer is in front of each service. For action plans, it includes findings with severity, current vs. required state, specific implementation steps, and a verification checklist.

The content varies but the envelope is consistent: `status` at the top, target agent identified, enough context to start without reading the full plan.

### Status Lifecycle

```
pending → in-progress → [triage →] [fixes-applied →] complete
                ↓
             failed
```

- `pending` — written by source agent, waiting for target
- `in-progress` — target agent has picked up, work started
- `triage` — (security only) audit complete, working through findings
- `fixes-applied` — Category A/B resolved, Category C action plans written
- `complete` — all work done
- `failed` — agent hit an unrecoverable error mid-task

The `failed` state is important. Without it, a session that crashed mid-audit would leave a `status: in-progress` file that looks active but isn't. When an agent fails, it sets `status: failed`, adds a `## Failure Reason` section explaining what went wrong and how far it got, and writes a memory note so other agents see it. The next session surfaces failed items alongside pending ones and the user decides whether to retry.

## Session-Start Discovery

Each agent's CLAUDE.md includes an "On Session Start" section that scans the relevant queue directories:

```
On session start:
1. Check ~/.claude/projects/security/audit-queue/ for status: pending or failed
2. Check ~/.claude/projects/security/action-plans/ for target: this-agent, status: pending
```

The scan is explicit — the agent reads directory listings and checks metadata files, not a daemon or watcher. This keeps the mechanism transparent and avoids background processes. If there's something pending, the agent mentions it before starting other work.

## Memory Pointer Redundancy

Queue directories are the authoritative source, but agents also write a short memory note when creating a handoff:

```markdown
---
tier: working
created: YYYY-MM-DD
source: claudebox
expires: YYYY-MM-DD   # 14 days out
tags: [security, handoff]
---

Security audit requested: <build-name> — YYYY-MM-DD
Request: ~/.claude/projects/security/audit-queue/<build-name>/request.md
```

This gets picked up by the working memory injection hook at the start of the target agent's session, before it even scans the queue directory. It's a belt-and-suspenders approach — if the directory scan misses something (unlikely but possible), the memory note catches it.

The 14-day expiry keeps these signals short-lived. Once a handoff is `complete`, the memory note ages out. The queue directory entry stays as a permanent record.

When an agent picks up a handoff and sets it `in-progress`, it writes a matching acknowledgment note:

```markdown
Security audit started: <build-name> — YYYY-MM-DD
```

This closes the loop — the source agent can see in its memory injection that the handoff was received, without any direct communication between the two.

## Action Plan Routing

The security agent produces action plans for findings that are too large for the current session or that require infrastructure access outside the security agent's scope. The `target-agent` field in `plan.md` determines where it goes:

| Target | Use when |
|--------|----------|
| `security` | Fix is self-contained to a security-audits repo or script |
| `claudebox` | Fix involves Docker compose, PM2, SWAG proxy confs, deploy scripts |
| `dev` | Fix involves code changes in application repos, MCP servers, CI/CD |
| `homelab-ops` | Fix spans multiple hosts or involves network-level infrastructure |

For non-security targets, the action plan directory gets a `handoff.md` alongside `plan.md`. This follows the same format as a build plan handoff — the target agent's session-start scan picks it up exactly the same way it picks up research handoffs.

Multi-agent findings (a finding that requires both a code change and an infrastructure change) get split into separate action plans, one per target agent, each scoped to only the work that agent should do.

## Git Commit Strategy

Every handoff-related file change is committed to version control. This makes the audit trail complete — you can look at git history on the audit queue or action plan directories and see exactly what was requested when, what the agent did, and when it was resolved.

The security-audits repo (separate from the context repo) gets an audit report committed before triage starts. If the session crashes mid-triage, the findings are already persisted. The triage summary is appended as a second commit when triage completes.

Commit message format for audit-related commits:

```
audit: <repo> YYYY-MM-DD — N critical, N high, N medium, N low
triage: <repo> YYYY-MM-DD — N fixed, N deferred, N accepted, N action plans
```

## Stale Monitoring

A resource monitor script (PM2 cron, runs every 6 hours) scans both queue directories for metadata files with `status: pending` that haven't been touched in more than 7 days. When it finds one, it sends a push notification naming the specific file and how long it's been waiting.

This catches the failure modes that the status lifecycle doesn't: a building agent wrote a request but the security agent never loaded that chat, or an action plan was routed to an agent that isn't being used. The 7-day threshold is long enough to avoid noise during normal gaps in usage but short enough to catch genuine forgotten handoffs.

## Standalone Value

You can use this pattern with any set of Claude Code agents without the security workflow. The core mechanism — queue directories, metadata files, session-start discovery — works for any handoff between agent chats. The security audit workflow is the most developed instance, but the same structure handles the build plan workflow and would handle a diagnostics workflow or dependency update workflow with no changes to the pattern.

The minimum to make it work: a shared filesystem, per-agent CLAUDE.md files with session-start scan instructions, and agreement on the directory layout and status field values.

## Gotchas

**Status drift.** If an agent session crashes after setting `status: in-progress` but before completing, the file is stuck. Build the `failed` state into your workflow from the start — it's easier to add than to retrofit when you first hit a crash.

**Scan order matters.** If an agent's session-start scan lists pending build plans AND pending action plans, show action plans first. Action plans represent work already committed to, whereas build plans are new work. The user should resolve existing obligations before taking on new ones.

**Don't put large context in the handoff file.** The handoff is a pointer and a brief. Put the full plan in `plan.md` and reference it. Agents load the handoff file on every session start — keep it short enough to scan quickly.

**Memory notes have a 14-day expiry for a reason.** If a handoff is still pending after 14 days, the memory note is gone but the queue directory entry is not. The stale monitor catches it. Don't extend memory note expiry trying to compensate for a slow-moving handoff — fix the monitoring instead.

---

## Related Docs

- [Architecture](../architecture.md) — build plan and security audit data flows
- [Architecture decisions](../decisions.md) — why file-based handoffs over a message bus
- [memory-sync](memory-sync.md) — working memory tier where handoff signals are written
