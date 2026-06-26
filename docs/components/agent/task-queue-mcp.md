# task-queue-mcp

task-queue-mcp is a containerized FastMCP server that exposes the forge agent task queue
as an MCP tool surface. Agents submit, retrieve, and transition tasks via MCP tool calls;
task state is persisted to per-task YAML files on disk. As of v0.3.0 it also serves a
shared-secret HTTP control API on the same port — the single validated mutation path for
non-MCP clients (the CloudCLI plugin and the Matrix bot).

- **Source:** `~/repos/personal/task-queue-mcp` (TadMSTR/task-queue-mcp)
- **Version:** v0.3.0
- **Port:** `127.0.0.1:8485` — MCP (`/mcp`) and the HTTP control API (`/tasks/...`) share it
- **Queue dir:** `~/.claude/task-queue/` (host-mounted)
- **Network:** `forge-net`
- **Wiring:** registered globally in `~/.claude.json`, so all Claude Code agent sessions
  have access (also proxied per-agent via scoped-mcp)

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

## Tool Surface

Eight tools, split by caller. Agents use the strict `update_task` path; operators (via the
HTTP control API) use the broader lifecycle tools. Agents cannot cancel — `cancelled` is
operator-only.

| Tool | Caller | What it does |
|------|--------|-------------|
| `submit_task` | agent | Create a new task (`status: submitted`); validates type, risk, priority, `workflow_mode` |
| `list_tasks` | agent | List tasks with optional filters; TTL-expired, archived, and quarantined tasks excluded |
| `get_task` | agent | Retrieve a task by full UUID (also resolves archived + quarantined) |
| `update_task` | agent | Strict status transition; appends a history entry |
| `set_task_status` | operator | Audited status change — approve, cancel, or advance a missed task (`allow_override`) |
| `cancel_task` | operator | Graceful terminal `cancelled` state for stale tasks (record kept) |
| `quarantine_task` | operator | Isolate a task to `quarantine/` (recoverable) |
| `restore_task` | operator | Restore a quarantined task to the active queue |

### Status lifecycle

```
submitted → [pending-approval] → approved → in-progress → completed
                                                 ↓
                                              failed

Any non-terminal ──(operator)──> cancelled        # graceful dismissal, record kept
Any task ──(operator quarantine)──> quarantine/    # isolate (recoverable via restore)
```

- **Non-terminal:** `submitted`, `pending-approval`, `approved`, `in-progress`
- **Terminal (immutable, even for operators):** `completed`, `failed`, `cancelled`

The dispatcher owns `submitted → approved / pending-approval`. Agents own
`approved → in-progress → completed` (or `failed`). Operators own `cancelled`,
quarantine/restore, and audited overrides. Approval gating is controlled by agent manifests
and the `requires_approval` field. `alert_state` and `retry_policy` are dispatcher-owned and
never touched by `update_task`.

The `workflow_mode` field (`semi-auto` default, or `auto`) controls dispatcher behavior:
`semi-auto` queues the task for operator pickup with a Matrix notification, `auto` launches
the target agent headlessly.

## HTTP Control API

Non-MCP clients can't import the Python core, so their mutations go through a thin HTTP
control API mounted as FastMCP custom routes on the **same port 8485**. Each route delegates
to the tool handlers above, inheriting transition validation, `fcntl` locking, and atomic
writes — so there is exactly one validated write path for the whole system (this ended the
prior three-writer divergence between the core, the plugin, and the bot).

| Method | Path | Delegates to |
|--------|------|--------------|
| `POST` | `/tasks/{id}/approve` | `set_task_status(approved)` |
| `POST` | `/tasks/{id}/cancel` | `cancel_task` |
| `POST` | `/tasks/{id}/status` | `set_task_status` (body: `status`, `note`, `allow_override`) |
| `POST` | `/tasks/{id}/quarantine` | `quarantine_task` |
| `POST` | `/tasks/{id}/restore` | `restore_task` |

**Auth.** Custom routes bypass the MCP middleware, so a shared-secret header gates them:
send `X-Task-Queue-Secret: $TASK_QUEUE_API_SECRET` on every mutation. The server compares it
in constant time (`hmac.compare_digest`) and **fails closed** (`401`) when the secret is
missing, wrong, non-ASCII, or unconfigured. The secret lives in `~/.secrets/forge.env` and
is injected via env into the container, bot, and plugin — never committed to source.

> **Deploy note:** secret provisioning is a separate sysadmin task. Until
> `TASK_QUEUE_API_SECRET` is provisioned in the environment, the control API fails closed and
> the plugin/bot mutation path is not live. The MCP tools are unaffected.

### Trust model

**Loopback is the trust boundary.** The shared secret gates only the cross-process HTTP
control routes — it is *not* the sole barrier to mutation. All MCP tools, including the
operator-mutating ones, are reachable via the unauthenticated `/mcp/` JSON-RPC endpoint, so
any process with loopback access to port 8485 can mutate the queue without the secret. This is
intentional: the queue is internal agent-coordination state, the port is loopback-only, and
the MCP transport has always been unauthenticated. The secret authenticates the *specific*
cross-process clients over plain HTTP, not the loopback boundary. If loopback trust ever
becomes insufficient, gate the MCP transport with a FastMCP auth provider rather than relying
on the control-route secret alone.

## Queue Directory Layout

```
~/.claude/task-queue/
  YYYYMMDD-HHMMSS-<uuid-prefix>.yml   # one file per active task
  archive/                            # TTL-expired tasks (dispatcher-owned)
  quarantine/                         # isolated tasks (recoverable via restore_task)
```

Each task file is a YAML record (type, payload, status history, `result.output`, `alert_state`,
`retry_policy`). All writes are atomic — write to `.tmp`, then `os.rename()` — and serialized
with per-task `fcntl.flock` locks to prevent races between concurrent MCP calls and the
dispatcher. Tasks are never hard-deleted: cancellation keeps the record, quarantine moves it
aside recoverably. Writes use `yaml.dump` (never string interpolation) to prevent YAML
injection.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TASK_QUEUE_DIR` | `/task-queue` | Queue directory inside the container (host `~/.claude/task-queue/`) |
| `MCP_HOST` | `0.0.0.0` | Bind host for the HTTP server |
| `MCP_PORT` | `8485` | Port for MCP + the HTTP control API |
| `TASK_QUEUE_API_SECRET` | — | Shared secret for the control API. **Required** for any control-API mutation — fails closed (`401`) if unset. MCP tools do not use it. |

## Scoped-MCP Registration

Registered in forge agent manifests that need task coordination:

```yaml
task-queue:
  type: mcp_proxy
  config:
    url: http://localhost:8485/mcp
```

Access is uniform across agents at the MCP layer (the operator/agent split is enforced by the
tools themselves and by the control-API secret, not by per-agent tool grants).

## Operations

```bash
# Health / reachability
curl -s http://127.0.0.1:8485/mcp -o /dev/null -w '%{http_code}\n'

# Container lifecycle (Docker stack)
docker compose -f ~/docker/task-queue-mcp/compose.yaml restart task-queue-mcp
docker logs task-queue-mcp --tail 50
```

## Related Docs

- [task-dispatcher.md](task-dispatcher.md) — routes and gates tasks; owns TTL archiving
- [matrix-task-queue-bot.md](matrix-task-queue-bot.md) — Matrix client of the control API
- [task-queue-widget.md](task-queue-widget.md) — dashboard widget client
- [agent-bus.md](agent-bus.md) — event logging alongside task state transitions
