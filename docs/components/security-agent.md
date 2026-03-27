# Security Agent

The security agent is a dedicated Claude Code project for post-build security audits. When a building agent (dev, claudebox, homelab-ops) deploys a service with a network surface, auth layer, or Docker exposure, it writes an audit request to a shared queue directory. The security agent picks up those requests on next session start, audits the build, triages findings with you, and routes fixes back to whichever agent owns the affected code.

It's a Layer 3 component — a Claude Code session with its own `CLAUDE.md`, scoped tooling, and file-based queue integration. No new services required.

- **Project directory:** `~/.claude/projects/security/`
- **Skill:** `security-triage` — interactive finding triage
- **Queue inbound:** `audit-queue/` (building agents write here)
- **Queue outbound:** `action-plans/` (security agent writes here)
- **Stale monitoring:** Integrated with resource-monitor (ntfy at 7 days)

## How It Fits In

The security agent fills the gap between "I just deployed something" and "I know whether it's safe." Building agents are focused on delivery — they make reasonable choices but aren't auditing their own work. The security agent audits without the bias of having just built the thing.

The workflow is fully async and file-based:

```
Building agent writes:
  ~/.claude/projects/security/audit-queue/<build-name>/request.md

Security agent (next session start) reads queue, audits, writes:
  ~/.claude/projects/security/action-plans/<build-name>/plan.md

Action plans route back to:
  - claudebox (Docker, PM2, proxy confs)
  - dev (code changes in app repos)
  - homelab-ops (multi-host or network changes)
```

For the underlying handoff mechanics — queue directory layout, status lifecycle, memory pointer redundancy — see [inter-agent-communication.md](inter-agent-communication.md).

## Prerequisites

- Claude Code CLI with per-project CLAUDE.md files
- `security-triage` skill deployed under `~/.claude/skills/`
- Shared filesystem with other agent projects (standard on a single host)

## Session Start Behavior

The security CLAUDE.md instructs the agent to scan both queue directories on every session start:

1. Check `audit-queue/` for requests with `status: pending` or `status: failed`
2. Check `action-plans/` for self-targeted plans (security agent fixing its own findings)
3. Cross-reference recent build memory notes and build plan handoffs against audit queue entries — flag any builds that completed without a corresponding audit request

If anything is pending, the agent reports it before other work. Step 3 catches builds where the `build-close-out` skill wasn't invoked — the security agent surfaces the gap so it can be resolved.

## Audit Process

### Writing an Audit Request

Building agents write a request file after completing a deployment. The `build-close-out` skill automates this — it writes the audit queue request, doc-update queue entries, touched-files tracker, and memory checkpoint in one step. Agents should invoke this skill as the final step of any build plan rather than writing the request manually.

The request file includes what was built, which repos changed, what ports are exposed, and what auth layer is in front of each service.

```markdown
# <build-name>

status: pending
target-agent: security
source-agent: claudebox
completed: YYYY-MM-DD

## Brief
One paragraph summary of what was deployed and why it warrants an audit.

## What Was Built
- Repo: TadMSTR/some-repo (commit abc1234)
- Exposed: port 3003 (localhost + Docker bridge only)
- Auth: SWAG token injection + Authelia SSO

## Files Changed
- src/routes/updates.js (new)
- config/config.js (modified)
```

Builds with no network or auth surface (pure config files, documentation changes) set `audit-status: not-requested` in their completion record and skip the queue entirely.

### Triage Categories

The security agent classifies every finding into one of three categories using the `security-triage` skill:

| Category | Meaning | Next Step |
|----------|---------|-----------|
| A | Auto-fix — clear remediation, self-contained | Agent fixes immediately in session |
| B | Discuss — tradeoffs, accepted risks, or priority decision needed | Triage conversation with you |
| C | Action plan — fix is large, multi-session, or outside security agent scope | Writes plan.md, routes to target agent |

Category A findings get fixed before triage starts. You see the fix summary during review. Category B findings get a recommendation — you decide whether to fix, defer, or accept the risk. Category C findings become action plans routed back through the handoff system.

### Audit Record

Before triage starts, the agent commits an audit report to a separate `security-audits` git repo. If the session crashes mid-triage, findings are already persisted. Triage summary is appended as a second commit when triage completes.

Commit format:
```
audit: <repo> YYYY-MM-DD — N critical, N high, N medium, N low
triage: <repo> YYYY-MM-DD — N fixed, N deferred, N accepted, N action plans
```

## Configuration

The security agent's `CLAUDE.md` is the primary configuration surface. It defines:

- **Queue directories** to scan on session start
- **Scope** — what the security agent will and won't touch (code changes to app repos route to dev, not done in the security session)
- **Triage format** — how findings are presented and how decisions are recorded
- **Action plan routing** — target-agent mapping by finding type

No environment variables or config files are needed beyond the `CLAUDE.md` and the `security-triage` skill.

## Stale Request Monitoring

The resource-monitor script (PM2 cron, runs every 6 hours) scans both queue directories for metadata files with `status: pending` older than 7 days. When it finds one, it sends a push notification naming the specific file and how long it's been waiting.

This catches the failure modes the status lifecycle doesn't: a building agent wrote a request, but the security project hasn't been opened since. The 7-day threshold is long enough to avoid noise during normal gaps but short enough to catch genuinely forgotten audits.

## Standalone Value

The security agent is usable independently of the rest of the Layer 3 stack. The only hard dependency is a Claude Code CLI installation with per-project CLAUDE.md support. The queue directories are plain directories on the filesystem — you can write audit requests manually without any other automation in place.

If you're running multiple Claude Code agent projects and want a lightweight way to audit new deployments without adding a service or a daemon, the pattern translates directly: one shared directory, one metadata file format, one session-start scan.

## Gotchas

**Scope creep.** The security agent is most useful when it stays in its lane. Resist the temptation to have it make code changes directly — route those back to the appropriate building agent. Mixed-scope sessions are harder to review and harder to repeat.

**Don't skip the failed state.** If a triage session crashes mid-audit, set `status: failed` in the request file with a note on how far it got. A stuck `in-progress` status looks like active work but isn't — the stale monitor won't catch it until 7 days have passed.

**Audit-free builds need a record too.** If a build has no security surface, document that decision in the completion record (`audit-status: not-requested`). An empty queue should mean "nothing to audit," not "someone forgot to check." The `build-close-out` skill handles this distinction — it asks whether the build has a security surface and writes the appropriate record either way.

## Related Docs

- [Inter-Agent Communication](inter-agent-communication.md) — queue directories, handoff format, status lifecycle
- [Architecture](../architecture.md) — security audit flow data flow diagram
- [Architecture Decisions](../decisions.md) — why post-build auditing, why file-based
