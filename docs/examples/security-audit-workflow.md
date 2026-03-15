# Security Audit Workflow — Example Walkthrough

This document shows a complete end-to-end example of the post-build security audit workflow,
from a building agent writing a completion report through triage and resolution.

All values are sanitized placeholders. Adapt paths, repo names, and service details to your
own setup.

---

## Step 1 — Building Agent Writes Completion Report

After deploying a new MCP server, the building agent writes:

`~/.claude/projects/security/audit-queue/my-mcp-server/request.md`

```markdown
# my-mcp-server

status: pending
source-agent: dev
build-plan: ~/.claude/projects/research/build-plans/my-mcp-server/handoff.md
completed: 2025-10-15

## What Was Built
Deployed a new MCP server that exposes tool endpoints for interacting with a local
database. Runs as a Docker container on port 8383, proxied internally via SWAG.

## Repos Changed
- `/home/user/repos/personal/my-mcp-server` — initial implementation — commit `abc1234`

## Files Modified
my-mcp-server/:
  src/index.ts
  src/tools/query.ts
  docker-compose.yml
  Dockerfile

## Services Deployed
- my-mcp-server — port 8383, HTTP, no external auth layer

## Exposure Surface
- Bound to 0.0.0.0:8383 (all interfaces)
- Proxied at mcp.yourdomain.internal — internal SWAG only, no Authelia

## Known Risks
- Port currently bound to all interfaces rather than localhost
- No request authentication beyond network isolation

## Audit Scope Hints
- Focus on input validation in src/tools/query.ts — accepts raw user input passed to DB
- Check Docker container privileges in Dockerfile
```

The building agent also writes a memory pointer to `~/.claude/memory/shared/`:

```markdown
---
tier: working
created: 2025-10-15
source: dev
expires: 2025-10-29
tags: [security, handoff]
---

Security audit requested: my-mcp-server — 2025-10-15
Request: ~/.claude/projects/security/audit-queue/my-mcp-server/request.md
```

---

## Step 2 — Security Agent Picks Up the Request

On session start, the security agent scans the audit queue, finds the pending request, and
updates it:

```markdown
status: in-progress
```

It writes a handoff acknowledgment to `~/.claude/memory/shared/`:

```markdown
---
tier: working
created: 2025-10-16
source: security
expires: 2025-10-30
tags: [security, handoff]
---

Security audit started: my-mcp-server — 2025-10-16
Request: ~/.claude/projects/security/audit-queue/my-mcp-server/request.md
```

---

## Step 3 — Audit Runs, Findings Produced

The `security-audit` skill runs against the repo and produces a findings report committed to
`/home/user/repos/audits/security-audits/2025-10-16-my-mcp-server.md`.

**Example findings:**

```
CRITICAL  AUTH-01  No authentication on MCP endpoint — accepts all requests from any LAN host
HIGH      INPUT-01 Raw user input passed to database query constructor without sanitization
MEDIUM    DOCKER-01 Container runs as root; no USER directive in Dockerfile  
LOW       BIND-01  Port bound to 0.0.0.0 instead of 127.0.0.1
INFO      LOG-01   Request logging disabled; no audit trail for tool calls
```

Request updated to `status: triage`.

---

## Step 4 — Triage with Category Breakdown

The security agent categorizes findings before presenting anything:

> Found 5 findings: 2 trivial fixes I'll apply now (BIND-01, LOG-01),
> 2 to discuss with you (AUTH-01, DOCKER-01), 1 action plan to route (INPUT-01 — requires
> code refactor across 3 files).

**Category A — Applied without interrupting:**
- `BIND-01`: Changed `0.0.0.0:8383` to `127.0.0.1:8383` in docker-compose.yml. Commit `def5678`.
- `LOG-01`: Enabled request logging via env var in docker-compose.yml. Commit `ghi9012`.

**Category B — Presented one at a time:**

> **AUTH-01** — No authentication on MCP endpoint
>
> The MCP server accepts requests from any host on the LAN without authentication. Any device
> on your network can call any tool, including ones that modify data.
>
> **Proposed fix:** Add Authelia middleware to the SWAG proxy config so only authenticated
> sessions can reach the endpoint.
>
> fix / defer / accept?

Ted: fix

> Applied. Updated SWAG conf at `/opt/appdata/swag/nginx/proxy-confs/my-mcp-server.subdomain.conf`.
> Commit `jkl3456`.

> **DOCKER-01** — Container runs as root
>
> The Dockerfile has no USER directive, so the process runs as root inside the container.
> If the app is compromised, the attacker has root in the container.
>
> **Proposed fix:** Add `USER node` directive after npm install step.
>
> fix / defer / accept?

Ted: defer — will address in next dev cycle

> Captured. Reason: deferred to next dev cycle.

**Category C — Action plan generated:**

`INPUT-01` requires sanitizing raw input before it reaches the database query constructor.
This spans three files (`src/tools/query.ts`, `src/tools/insert.ts`, `src/db/client.ts`) and
needs tests. Routed to dev agent.

---

## Step 5 — Action Plan Written

`~/.claude/projects/security/action-plans/2025-10-16-my-mcp-server-input01/plan.md`:

```markdown
# Security Action Plan — my-mcp-server — 2025-10-16

source-audit: /home/user/repos/audits/security-audits/2025-10-16-my-mcp-server.md
target-agent: dev
status: pending

## Findings to Address

### INPUT-01 — Unsanitized input passed to database query constructor

- Severity: High
- Current state: `src/tools/query.ts` passes `params.query` directly to `db.query()`
  without validation or parameterization
- Required state: All database calls use parameterized queries; input validated at tool
  boundary before reaching DB layer
- Approach:
  1. Replace raw string concatenation in `db.query()` calls with parameterized form
  2. Add input schema validation at tool boundary in `src/tools/query.ts`
  3. Repeat for `src/tools/insert.ts` and any other tools using the same pattern
  4. Add tests covering SQL injection attempts
- Files to modify:
  - src/tools/query.ts
  - src/tools/insert.ts
  - src/db/client.ts
  - tests/tools/query.test.ts (add injection test cases)
- Testing: Run injection test suite; verify parameterized query format in logs
- Risk: Schema validation may reject existing valid inputs — review tool callers before
  tightening validation

## Implementation Order
1. INPUT-01 — single finding, complete before marking done

## Verification Checklist
- [ ] No raw string concatenation in DB calls
- [ ] Input schema validation present at each tool entry point
- [ ] Test cases cover common injection patterns
- [ ] Audit report updated with fix commit hash
```

Alongside it, `handoff.md` for the dev agent:

```markdown
# Security Action Plan — my-mcp-server INPUT-01

target: dev
status: pending
plan: ~/.claude/projects/security/action-plans/2025-10-16-my-mcp-server-input01/plan.md
source-audit: /home/user/repos/audits/security-audits/2025-10-16-my-mcp-server.md

## Brief
SQL injection risk: raw user input passed directly to database query constructor.
Requires parameterized queries and input validation across 3 source files + tests.
Category C finding from 2025-10-16 security audit.
```

---

## Step 6 — Audit Closed Out

Triage summary appended to the audit report, `request.md` updated to `status: complete`,
updated report committed:

```
triage: my-mcp-server 2025-10-16 — 2 fixed, 1 deferred, 1 accepted, 1 action plan
```

---

## What Happens Next

The dev agent picks up the action plan at session start (it scans
`~/.claude/projects/security/action-plans/` for `target: dev, status: pending`), implements
the fix, and updates `status: complete` on the `handoff.md`.

The security agent may do a spot-check verification in a future session by scanning
`action-plans/` for recently completed items.

---

*See [Inter-Agent Communication](../components/inter-agent-communication.md) for the generic
pattern this workflow uses.*
