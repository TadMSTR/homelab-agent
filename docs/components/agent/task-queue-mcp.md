# task-queue-mcp

task-queue-mcp is a containerized FastMCP server that exposes the forge agent task queue
as an MCP tool surface. Agents submit, retrieve, and transition tasks via MCP tool calls;
task state is persisted to per-task YAML files on disk. As of v0.3.0 it also serves an HTTP
control API on the same port for non-MCP clients (the CloudCLI plugin and the Matrix bot) —
the single validated mutation path for everything that can't import the Python core. As of
v0.11.0 that API also serves authenticated **reads**, gated by its own per-client scoped
tokens rather than the one shared secret it used through v0.10.x — see
[HTTP Control and Read API](#http-control-and-read-api) below.

- **Source:** `~/repos/personal/task-queue-mcp` (TadMSTR/task-queue-mcp)
- **Version:** v0.13.0 — deployed as a pinned, published GHCR image (not a local build) —
  see [Deployment](#deployment)
- **Port:** `127.0.0.1:8485` — MCP (`/mcp`) and the HTTP control/read API (`/tasks/...`)
  share it
- **Queue dir:** `~/.claude/task-queue/` (host-mounted)
- **Network:** `forge-net`
- **Wiring:** registered globally in `~/.claude.json`, so all Claude Code agent sessions
  have access (also proxied per-agent via scoped-mcp, with a per-agent bearer token header)

## Container Hardening

```yaml
user: "1000:1000"
cap_drop: [ALL]
security_opt: [no-new-privileges:true]
read_only: true
tmpfs: /tmp
```

The container filesystem is read-only. Only the mounted task queue directory and `/tmp`
are writable. The port is not proxied externally via SWAG and the host firewall blocks
external access — reachable on loopback/LAN only.

Since v0.13.0 the container runs from a published, digest-pinned GHCR image rather than a
local build — see [Deployment](#deployment).

## Tool Surface

Ten tools, split by caller. Agents use the strict `update_task` path; operators (via the
HTTP control API) use the broader lifecycle tools. Agents cannot cancel or park — both are
operator-only. `amend_task` is the exception: the task's *source* agent may amend it, but
the target agent may not — the same trust boundary that keeps `cancelled` operator-only,
applied to rewriting a task's own brief.

As of v0.4.0, `quarantine_task` / `restore_task` are removed entirely — `park_task` /
`unpark_task` replace them, and `amend_task` is new. As of v0.8.0, the caller column below
is enforced, not just conventional — see [Identity binding](#identity-binding-since-v080).
As of v0.10.0, `requeue_dead_letter` joins the operator-only row — see
[Queue Directory Layout](#queue-directory-layout) for what it recovers from.

| Tool | Caller | What it does |
|------|--------|-------------|
| `submit_task` | agent | Create a new task (`status: submitted`); validates type, risk, priority, `workflow_mode`. `source_agent` is bound to the caller's authenticated identity |
| `list_tasks` | agent | List tasks with optional filters; TTL-expired *terminal* tasks and archived tasks excluded. Non-terminal tasks (any open work) are never TTL-filtered as of v0.8.1 — see [TTL and visibility](#ttl-and-visibility) |
| `get_task` | agent | Retrieve a task by full UUID (also resolves archived tasks, and dead-lettered tasks as of v0.10.0) |
| `update_task` | the task's target agent, or operator | Strict status transition; appends a history entry |
| `set_task_status` | **operator only** | Audited status change — approve, cancel, park, or advance a missed task (`allow_override`). Refused for any agent identity as of v0.8.0 |
| `cancel_task` | **operator only** | Graceful terminal `cancelled` state for stale tasks (record kept). Refused for any agent identity as of v0.8.0 |
| `park_task` | the task's target agent, or operator | Pause a task without hiding it — status changes to `parked`, the YAML file never moves, stays listed, exempt from TTL |
| `unpark_task` | the task's target agent, or operator | Return a parked task to the status recorded in `parked_from` (or an explicit target status) |
| `amend_task` | the task's source agent, or operator | Append a correction to a queued task. `payload.description` is never rewritten; amendments accumulate under `payload.amendments`, capped at 10 per task / 4096 chars each |
| `requeue_dead_letter` | **operator only** | Return a dead-lettered task to the queue root at `submitted`, dropping `failed_reason` and resetting `retry_policy`. Since v0.10.0 — the only tool that can move a record out of a terminal status |

Every record returned by `get_task`/`list_tasks` carries **`queue_location`**
(`"queue"` | `"archive"` | `"dead-letters"`, since v0.10.0), so a caller can tell a dead
letter from live work without inspecting file paths, which it never sees.

### Status lifecycle

```
submitted → [pending-approval] → approved → in-progress → completed
                                                 ↓
                                              failed

Any non-terminal ──(operator)──> cancelled      # graceful dismissal, record kept
Any non-terminal <──(operator)──> parked        # pause; stays listed, TTL-exempt, reversible
```

- **Non-terminal:** `submitted`, `pending-approval`, `approved`, `in-progress`, `parked`
- **Terminal (immutable, even for operators):** `completed`, `failed`, `cancelled`

`parked` is a **status**, not a relocation — unlike the old quarantine mechanism, which
moved a task's YAML into a `quarantine/` subdirectory that no reader listed. A parked task
keeps its file exactly where it is, keeps showing up in `list_tasks`, and renders muted
with an Unpark button in the CloudCLI plugin.

The dispatcher owns `submitted → approved / pending-approval`. Agents own
`approved → in-progress → completed` (or `failed`). Operators own `cancelled`, `parked`,
and audited overrides. Approval gating is controlled by agent manifests and the
`requires_approval` field. `retry_policy` is dispatcher-owned and never touched by
`update_task`. `alert_state` is retired as of v0.4.0 and no longer written on task
creation — existing task YAMLs keep an inert copy for continuity, not as a migration miss.

The `workflow_mode` field (`semi-auto` default, or `auto`) controls dispatcher behavior:
`semi-auto` queues the task for operator pickup with a Matrix notification, `auto` launches
the target agent headlessly.

### TTL and visibility

`list_tasks` still excludes **terminal** tasks (`completed`, `failed`, `cancelled`) past
their `ttl_days` — finished work is meant to age out of the default view. As of v0.8.1
(vikunja#395), **no non-terminal status is TTL-filtered anymore**. Every open task stays
visible however old it is. This closed a real blind spot, not a hypothetical one: a queue
sweep found 17 stranded tasks where `list_tasks` had reported only 13 — the four oldest had
aged past `ttl_days` and vanished from the listing used to count them, while still sitting
on disk waiting for someone. Nothing that is still someone's responsibility should be hidden
by a clock; an agent handed a stale open task can judge it, but nobody can act on a task they
cannot see. Whenever "how many are there" is answered by `list_tasks`, remember it filters —
count from the queue directory directly if the exact number matters.

**Dead letters (since v0.10.0).** `list_tasks(include_dead_letters=True)` also returns
records the dispatcher gave up routing and moved to `dead-letters/`. It defaults to `False`
and is deliberately **not** implied by `include_archived` — every agent's work sweep is a
plain `list_tasks` call, and a dead letter is a task nothing can route, so folding it into
the default listing would hand each agent a backlog it cannot act on. This is visibility,
not re-delivery.

Two behaviours make the flag work against a real queue rather than a fixture, and both were
found by running it against the live one:

- Dead letters carry terminal `failed`, and every one on forge is already past its
  `ttl_days` — the newest by a month, the oldest by three. **Dead letters are exempt from
  the TTL filter**, or `include_dead_letters=True` returns an empty list against the only
  queue that has any, which reads as "there are none".
- A dead letter is among the oldest records in the queue by construction, so under a plain
  created-descending sort it lands behind hundreds of live tasks and `limit` discards it.
  **Dead letters sort first when included.** Measured before the fix:
  `include_dead_letters=True, limit=200` returned 200 rows and zero dead letters. Ordering
  within each group is unchanged.

## HTTP Control and Read API

Non-MCP clients can't import the Python core, so they read and write the queue through a
thin HTTP API mounted as FastMCP custom routes on the **same port 8485**. Each route
delegates to the tool handlers above, inheriting transition validation, `fcntl` locking,
atomic writes, and (since v0.11.0) the TTL and dead-letter rules — so there is one validated
write path and one read path for the whole system, instead of every client parsing the
queue YAML itself (this ended the prior three-writer divergence between the core, the
plugin, and the bot, and the divergent-reader problem that preceded it).

| Method | Path | Scope | Delegates to |
|--------|------|-------|--------------|
| `GET` | `/tasks` | `read` | `list_tasks`, plus `count` and `truncated` — see below |
| `GET` | `/tasks/{id}` | `read` | `get_task`: queue, `archive/`, then `dead-letters/` |
| `GET` | `/queue/summary` | `read` | Counts by status across the active queue, plus `dead_letters` |
| `POST` | `/tasks/{id}/approve` | `operator-write` | `set_task_status(approved)` |
| `POST` | `/tasks/{id}/cancel` | `operator-write` | `cancel_task` |
| `POST` | `/tasks/{id}/status` | `operator-write` | `set_task_status` (body: `status`, `note`, `allow_override`) |
| `POST` | `/tasks/{id}/park` | `operator-write` | `park_task` |
| `POST` | `/tasks/{id}/unpark` | `operator-write` | `unpark_task` (body: optional `status`) |
| `POST` | `/tasks/{id}/amend` | `operator-write` | `amend_task` (body: `amendment`, optional `reason`) |
| `POST` | `/tasks/{id}/update` | `operator-write` | `update_task` (body: `status`, `note`, `output`, optional `on_behalf_of`) — the operator sweep, see below |
| `POST` | `/tasks/{id}/requeue` | `operator-write` | `requeue_dead_letter` (body: optional `note`), since v0.10.0 |

`GET /queue/summary` moved from `operator-write` to `read` in v0.11.0 — a behaviour change
from earlier releases, not just an addition. Responses map the canonical result: `200` ok,
`404` not found, `400` validation/transition error. Auth failures are `401` (no valid token)
or `403` (a valid token lacking the route's scope).

**Auth: per-client scoped tokens (since v0.11.0).** Through v0.10.x every custom route,
including the only read route, was gated by one shared secret —
`X-Task-Queue-Secret: $TASK_QUEUE_API_SECRET`. That secret turned out to be ambient rather
than held by its three intended clients: a `/proc` sweep on forge found it in 23 `ted`-owned
processes, including every session the CloudCLI host launched (vikunja#396). v0.11.0
replaced it with one token per client, each with its own scopes:

```bash
TASK_QUEUE_CLIENT_CLOUDCLI=sha256:<64 lowercase hex>
TASK_QUEUE_CLIENT_SCOPES_CLOUDCLI=read,operator-write
```

- **Scopes** (`read`, `operator-write`) are a closed vocabulary; neither implies the other.
- **Header:** the plaintext token travels as `X-Task-Queue-Token`, **never**
  `Authorization`. FastMCP's authentication middleware runs on every route, not only `/mcp`,
  so a valid *agent* bearer would otherwise authenticate a custom-route request at the
  Starlette layer even though the route never checks it. Client tokens use their own header
  specifically so that a client token grants nothing on `/mcp` and an agent bearer grants
  nothing here.
- **Digests only, server-side.** The server stores `sha256(token)`, never the plaintext —
  reading its env file yields no usable credential. This is a real boundary only for a
  client whose plaintext lives under a separate OS user; for the CloudCLI plugin and the
  Matrix bot, both of which run as `ted` like every agent, it buys containment and
  attribution (revocable, no longer ambient) rather than a boundary.
- The server **refuses to start** on a malformed digest, a digest shared by two clients, an
  empty or unknown scope, a channel named `operator` or after an agent identity, or a client
  digest equal to an agent token's.
- **`TASK_QUEUE_API_SECRET` is gone as of v0.12.0.** The shared-secret path (and the
  `legacy-shared` transitional channel v0.11.0 briefly accepted it under) is deleted
  outright. If the variable is still set, the server logs a startup warning to delete it;
  setting it again re-enables nothing, and a request carrying only the old header gets a
  flat `401`.

**`actor` is pinned to `operator`** on every one of these routes and is not read from the
body (since v0.8.0) — a future non-operator client here cannot quietly acquire the identity
every ownership check exempts.

**Every write now records its `channel`** (since v0.11.0): which client made it. `actor`
says the operator acted; `channel` says through what.

```yaml
history:
  - timestamp: ...
    status: approved
    actor: operator
    channel: matrix-bot
    note: ""
```

MCP tool calls write no `channel`, and records written before v0.11.0 are not rewritten.

### Reading the queue — `GET /tasks`, `GET /tasks/{id}`

`GET /tasks` takes the same filters as `list_tasks` (`target_agent`, `source_agent`,
`status`, `task_type`, `include_archived`, `include_dead_letters`) plus `limit` (default
200, max 1000), and returns `{"ok": true, "tasks": [...], "count": 612, "truncated": true}`.
`count` is how many records **matched**, not how many came back; `truncated` is true
whenever that's more than `len(tasks)`. The bare-list MCP tool has no way to say it cut
anything off — that silence is how a dead-letter listing once returned 200 rows and missed
exactly the records it was asked for. A client rendering this should show `truncated`, not
hide it. An unknown status, an unrecognised query parameter, a non-boolean flag, or a
`limit` outside 1–1000 is a `400` rather than a silently-unfiltered or silently-clamped
response.

**Read performance (since v0.13.0).** Task files are parsed with libyaml's `CSafeLoader`
— `yaml.safe_load` is hard-wired to the pure-Python `SafeLoader` regardless of whether
libyaml is installed, and the two produced byte-identical output across every file in the
live queue. A lookup by id, for `get_task` and every mutation, now parses only the file
named for the id's first 8 hex characters; a miss falls back to the existing full scan and
logs a warning naming the misnamed file, so a record whose filename doesn't match its id is
still found, never reported `404`. Every HTTP route runs its handler on a worker thread, the
same way FastMCP already runs synchronous MCP tools, so one slow scan no longer blocks every
other caller — concurrent writes to one task are still serialised by its `fcntl` lock.
Measured on the live queue: `GET /tasks?limit=1000` went from 0.95 s to about 0.11 s, and a
single archived-record lookup from 2.67 s to about 0.002 s.

### The operator sweep — `POST /tasks/{id}/update`

The only path to a terminal transition on **another agent's** task, added in v0.8.0. It
replaces a dishonest pattern: before identity binding, an agent could tidy up a stranded task
belonging to a different agent by simply passing that agent's name as `actor` on `update_task`
— 17 tasks were swept that way during `task-queue-lifecycle-and-doc-queue-2026-08`, correctly
outcome-wise but with a self-asserted, unverifiable `actor`. Binding `actor` to the bearer
token closes that route entirely, so a real replacement was needed for the legitimate case:
an operator closing a task nobody is coming back to claim.

Pass `on_behalf_of` naming the agent whose task it is. The handler verifies it against the
task's actual `target_agent` — a mismatch is a `400`, since an operator closing a
misidentified task should be told, not have the mistake recorded as deliberate — and writes
**both** names into history:

```yaml
history:
  - timestamp: ...
    status: completed
    actor: operator
    on_behalf_of: developer
    note: "stranded; swept during queue cleanup"
```

A sweep reads as a sweep years later, not as the agent having quietly closed its own work.
`on_behalf_of` is optional (omitting it is the operator acting in its own name) and is refused
outright for any non-`operator` actor.

### Recovering a dead letter — `POST /tasks/{id}/requeue` (since v0.10.0)

A dead letter cannot be transitioned in place. `update_task`, `set_task_status`,
`park_task`/`unpark_task`, and `amend_task` do not load `dead-letters/` at all — that
absence is the gate — and they refuse by name (`task is dead-lettered and cannot be
mutated in place`) rather than answering `not found`. `requeue_dead_letter` is the only
door out, and it is scoped to that one directory: a `failed` task sitting in the queue root
or in `archive/` is unreachable through it however its id is spelled, so terminal
immutability elsewhere is unchanged.

Requeuing moves the record back to the queue root at `submitted`, drops `failed_reason`,
and resets `retry_policy` to `{next_retry_at: null, retry_count: 0}`. `created` is **not**
refreshed — rewriting it to make a three-month-old dropped audit look new is the flavour of
tidiness that made this backlog invisible in the first place. The history entry carries
`action: requeue` and `cleared_failed_reason`, so a second drop does not read as a first.

Operator-only, the same gate as `set_task_status` — an agent able to requeue its own dead
letters would turn a routing bug into an agent-driven retry loop with nothing bounding it.

Requeuing does not fix *why* a task was dropped. Do not describe it as a fix for the
underlying routing failure — that is recovery only; the root cause is tracked separately
(vikunja#63).

## Authentication

Both surfaces on port 8485 now require a credential — this is the headline change of the
`task-queue-identity-hardening-2026-08` build (v0.7.0 → v0.8.2), deployed and verified live
2026-08-16.

**MCP tool path (`/mcp`).** Was unauthenticated through v0.6.1 — any caller on `forge-net` or
loopback could invoke any tool while asserting any `actor`, including `operator`. As of
v0.7.0 it requires a per-agent bearer token, `TASK_QUEUE_TOKEN_<AGENT>`, verified by FastMCP's
`StaticTokenVerifier`. **The server refuses to start with no tokens configured at all** — this
cannot silently fail open. Missing or unknown token → `401`.

**HTTP control routes** use a separate mechanism — see
[Auth: per-client scoped tokens](#reading-the-queue--get-tasks-get-tasksid) above. Through
v0.10.x they were gated by one shared secret; since v0.11.0 each client holds its own
scoped token, and since v0.12.0 the shared secret grants nothing at all.

### Identity binding (since v0.8.0)

`actor` is **derived from the bearer token**, not taken from the caller. Passing a name that
does not match the authenticated identity is refused rather than silently corrected — a wrong
name in a call is a bug worth surfacing, not something to paper over. Omitting `actor` is
fine; it is filled in from the token. This is what makes `completed_by` and
`history[].actor` **evidence rather than claims**.

This also covers `source_agent` on `submit_task`, which is an identity claim and not just a
label: the submit-time auto-close (see the [task-queue-mcp README](https://github.com/TadMSTR/task-queue-mcp#auto-close-of-the-originating-task-since-v060))
decides whether to fire from `source_agent`/`target_agent`, so spoofing it would terminally
close another agent's task without ever calling `update_task`.

### Capability rules

| Tool | Who may call it |
|---|---|
| `submit_task`, `list_tasks`, `get_task` | any authenticated agent (`source_agent` bound to the caller) |
| `update_task` | the task's `target_agent`, or the operator |
| `park_task`, `unpark_task` | the task's `target_agent`, or the operator |
| `amend_task` | the task's `source_agent`, or the operator |
| `set_task_status`, `cancel_task`, `requeue_dead_letter` | **operator only** — refused for any agent identity |

The `operator` identity is reachable **only** from the HTTP control routes — a
`TASK_QUEUE_TOKEN_OPERATOR` is rejected at startup, because `operator` is exempt from every
ownership check and a token minting it on the agent-facing transport would hand its holder
the whole queue.

### Trust model

Follow this framing exactly — it is deliberately narrower than "the queue is secure":

> **What this does and does not buy.** It contains a *mistaken or prompt-injected* agent
> acting through its own tool surface, and it makes the audit trail mean what it says. It is
> deliberately **not** a boundary against an agent that goes looking for credentials: where
> agents hold a shell tool and run as the same OS user that owns the secret files, any token
> on the host is readable by any of them. Closing that needs per-agent OS users or a
> credential broker, and is out of scope for this server.

That residual gap was tracked as vikunja#396 — `TASK_QUEUE_API_SECRET` was ambient in every
agent's environment, so the control routes were agent-reachable as `operator` by an agent
willing to read its own env and call the HTTP API directly. **Closed as of v0.12.0**: the
shared secret is gone, and each HTTP client now holds its own scoped, revocable token
(see [Auth](#reading-the-queue--get-tasks-get-tasksid) above). This closes the *ambient,
shared-across-everything* half of the gap. It does not, and cannot from inside this server,
close the underlying one: agents still run as the same OS user (`ted`) as the clients whose
token files they could, in principle, read. A client token's value is contained and
attributable rather than secured against a co-resident process with shell access — the same
framing as the MCP bearer tokens above.

### Deployment prerequisite and order

The per-agent tokens are not optional configuration — the server will not start without at
least one. **Deploy order matters and is not reversible in practice:**

1. Tokens into each agent's `.env` file (`TASK_QUEUE_TOKEN=<value>`) — inert until step 3.
2. Manifests deployed (`agent-manifests-deploy.sh`) + each `scoped-mcp-<agent>` restarted —
   still inert; a bearer header sent to a server with no auth configured is ignored.
3. `TASK_QUEUE_TOKEN_<AGENT>` values into the server's env file, then **rebuild** (not just
   restart) the container — this is the step that closes the gate.

Reversing the order — closing the gate before every agent holds a valid token — locks every
agent out of the queue at once, because scoped-mcp's manifest loader raises on start if a
manifest references an undefined `${TASK_QUEUE_TOKEN}`. Rollback is simply removing the
`TASK_QUEUE_TOKEN_*` lines from the server's env file and rebuilding; that reopens the
pre-v0.7.0 gap but restores service without touching manifests or agent env files.

HTTP client tokens (`TASK_QUEUE_CLIENT_<NAME>` / `TASK_QUEUE_CLIENT_SCOPES_<NAME>`) follow
the same append-before-cut shape: mint and distribute each client's plaintext token first,
confirm it authenticates, only then delete `TASK_QUEUE_API_SECRET` and restart every process
that still held it. Deleting the secret before every client has migrated locks every
HTTP-only client out at once, the same failure mode as the MCP token case above.

## Queue Directory Layout

```
~/.claude/task-queue/
  YYYYMMDD-HHMMSS-<uuid-prefix>.yml   # one file per active task
  archive/                            # TTL-expired tasks (dispatcher-owned)
  dead-letters/                       # routing-exhausted tasks (dispatcher-owned)
```

A parked task's file stays in place at the top level — parking is a status change, not a
move, so there is no separate directory for it (the old `quarantine/` subdirectory is gone
as of v0.4.0).

`dead-letters/` is written by **task-dispatcher**, not by this server, when a task
exhausts its routing retries — it is the one directory no ordinary transition can reach (see
[Recovering a dead letter](#recovering-a-dead-letter--post-tasksidrequeue-since-v0100)
above). Until v0.10.0 nothing in task-queue-mcp could read this directory at all: `get_task`
searched the queue root then `archive/` and answered `not found` for a record sitting right
there, `list_tasks` globbed the root only, and `/queue/summary` counted the root only. 17
tasks accumulated here between 2026-05-29 and 2026-07-25 — every one a security audit
request, all carrying the identical `failed_reason` — and the only notice any of them ever
got was a single Matrix message at the moment each was dropped.

A dead-letter record carries a `failed_reason` block alongside the normal task fields:

```yaml
status: failed
failed_reason:
  reason: "Invalid or missing build_name in payload: 'unknown'"
  timestamp: ...
  retry_count: 3
```

The directory name (`dead-letters`) is presently an ungated literal shared between this
server and task-dispatcher — identical today, but not enforced equal by any test. Flagged
in the Phase 1 audit as the same drift class the parent build's later phases gate for other
cross-repo vocabulary; not yet closed for this one.

Each task file is a YAML record (type, payload, status history, `result.output`, `parked_from`,
`retry_policy`). All writes are atomic — write to `.tmp`, then `os.rename()` — and serialized
with per-task `fcntl.flock` locks to prevent races between concurrent MCP calls and the
dispatcher. Tasks are never hard-deleted: cancellation and parking both keep the record in
place. Writes use `yaml.dump` (never string interpolation) to prevent YAML injection.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TASK_QUEUE_DIR` | `/task-queue` | Queue directory inside the container (host `~/.claude/task-queue/`) |
| `MCP_HOST` | `0.0.0.0` | Bind host for the HTTP server |
| `MCP_PORT` | `8485` | Port for MCP + the HTTP control/read API |
| `TASK_QUEUE_CLIENT_<NAME>` | — | `sha256:<hex>` digest of one HTTP client's token, e.g. `TASK_QUEUE_CLIENT_CLOUDCLI`. Needs a matching `TASK_QUEUE_CLIENT_SCOPES_<NAME>`. Since v0.11.0 — see [Auth](#reading-the-queue--get-tasks-get-tasksid) |
| `TASK_QUEUE_CLIENT_SCOPES_<NAME>` | — | Comma-separated scopes for that client: `read`, `operator-write`, or both |
| `TASK_QUEUE_API_SECRET` | — | **Removed in v0.12.0.** Ignored; if still set, the server logs a startup warning to delete it. Never used by the MCP tools |
| `TASK_QUEUE_TOKEN_<AGENT>` | — | Per-agent bearer token for the MCP tool path, e.g. `TASK_QUEUE_TOKEN_DEVELOPER`. **At least one is required** — the server refuses to start with none. Suffix lowercased with `_` → `-` becomes the agent identity (`TASK_QUEUE_TOKEN_DOC_HEALTH` → `doc-health`). Each agent needs its own distinct token — a shared, empty, sub-16-character, or `operator`-named token is refused at startup. |

## Scoped-MCP Registration

Registered in forge agent manifests that need task coordination, with the agent's own token
injected as a bearer header (resolved from that agent's `.env`):

```yaml
task-queue-mcp:
  type: mcp_proxy
  config:
    url: http://localhost:8485/mcp
    headers:
      Authorization: "Bearer ${TASK_QUEUE_TOKEN}"
    # sysadmin's surface is scoped further, as of the same build:
    # tool_allowlist: [submit_task, list_tasks, get_task, update_task, amend_task]
    # — set_task_status/cancel_task/park_task/unpark_task are operator-only anyway
    # (see Capability rules above); the allowlist just keeps them off the agent's
    # visible tool list rather than relying solely on the server-side refusal.
```

Tool access is now genuinely per-agent, not uniform: which agent a caller is determines what
it may do, enforced by [identity binding](#identity-binding-since-v080) at the server, not
just by manifest-level tool grants.

## Deployment

Since v0.13.0, forge runs a **published, pinned GHCR image**
(`ghcr.io/tadmstr/task-queue-mcp:vX.Y.Z@sha256:<digest>`) rather than building from the
working tree. The release workflow builds and smoke-tests the image, attests build
provenance, and verifies that attestation inside the same CI job before publishing — forge's
own `gh` predates the `attestation` command entirely, so that in-job check is the only place
provenance can be confirmed (vikunja#1004). A deploy pulls the tag, confirms the pulled
`RepoDigests` matches the digest recorded in the GitHub Release notes, and swaps the
compose file's `build:` block for `image:`. The startup log names which YAML loader is
active (`CSafeLoader` is the fast path) — that is the line to check after any redeploy.

## Operations

```bash
# Health / reachability — now 401 without a valid bearer token, not 200; a non-401/200
# response (connection refused, 5xx) is what indicates the server itself is down
curl -s http://127.0.0.1:8485/mcp -o /dev/null -w '%{http_code}\n'

# Container lifecycle — since v0.13.0 this pulls and swaps a pinned, published image
# (see Deployment above) rather than rebuilding from the working tree. Restart alone is
# fine for picking up an env-file-only change.
docker compose -f ~/docker/task-queue-mcp/compose.yaml pull
docker compose -f ~/docker/task-queue-mcp/compose.yaml up -d
docker logs task-queue-mcp --tail 50
```

## Status Visibility (Matrix)

task-queue-mcp itself has no notification path — status visibility for agents and Ted
comes from [matrix-task-queue-bot](matrix-task-queue-bot.md), which watches the same
`~/.claude/task-queue/` directory this server manages. As of 2026-07-23 (commit
`e9f6f26`) the bot's old per-task stale-approval alert (a Matrix ping for any task
`approved` >24h) was removed — it had become a notification firehose — in favor of two
passive mechanisms: a pinned, self-editing status board per agent, and a single daily
morning-brief digest. [task-dispatcher](task-dispatcher.md)'s matching
`alert_stale_approved` feature was removed the same day for the same reason.

## Related Docs

- [task-dispatcher.md](task-dispatcher.md) — routes and gates tasks; owns TTL archiving
- [matrix-task-queue-bot.md](matrix-task-queue-bot.md) — Matrix client of the control API; pinned boards + morning brief
- [task-queue-widget.md](task-queue-widget.md) — dashboard widget client
- [agent-bus.md](agent-bus.md) — event logging alongside task state transitions
