# Task Queue MCP

task-queue-mcp is a FastMCP (Python) server that exposes the agent orchestration task queue as an MCP tool interface. It gives Claude Code sessions and LibreChat agents structured, validated access to `~/.claude/task-queue/` YAML files — replacing raw file writes with type-checked tools that enforce the schema and transition rules the dispatcher expects.

It runs as a Docker container on port 8485 and is wired globally into `~/.claude/settings.json` so all agent sessions have access.

## Why a Dedicated MCP Server

Agents that interact with the task queue via raw file I/O are fragile. The YAML schema has constraints — UUID format for IDs, enumerated status values, absolute paths in `context_refs`, append-only history — that are easy to violate when writing directly. A malformed task file can silently fail or trigger spurious dispatcher errors.

task-queue-mcp centralizes validation and enforces transition rules at the tool boundary. Agents call `submit_task` or `update_task`; the server handles schema conformance, atomic writes, and status guard rails. The dispatcher reads files it can trust.

## Tools

| Tool | Description |
|------|-------------|
| `submit_task` | Create a new task YAML in `~/.claude/task-queue/` with `status: submitted` |
| `list_tasks` | List tasks, optionally filtered by status or target agent. TTL-expired terminal tasks excluded. |
| `get_task` | Retrieve a single task by UUID |
| `update_task` | Transition a task's status and append a history entry |

### submit_task

Creates a new task file. Generates a UUID4 `id`, sets `created` to the current UTC timestamp, and writes with `status: submitted`.

```json
{
  "source_agent": "research",
  "target_agent": "claudebox",
  "task_type": "build",
  "risk_level": "low",
  "summary": "Deploy qmd stack update per plan",
  "payload": {
    "description": "Apply the qmd stack update from the build plan...",
    "context_refs": ["/home/ted/.claude/projects/research/build-plans/qmd-update/plan.md"],
    "priority": "normal"
  },
  "ttl_days": 30
}
```

**Validated fields:**
- `risk_level`: must be one of `low`, `medium`, `high`
- `task_type`: free-form string, but dispatcher routing depends on consistency with manifest `capabilities` — use established values (`build`, `deploy`, `fix`, `research`, `review`, `audit`, `notify`)
- `context_refs`: each entry must be an absolute path (starts with `/`)
- `target_agent`: free-form string or `"auto"` for dispatcher auto-routing

### list_tasks

Returns all tasks in `~/.claude/task-queue/`, excluding archived files. Optional filters:

```json
{
  "status": "approved",
  "target_agent": "claudebox"
}
```

TTL filtering applies: completed and failed tasks past their `ttl_days` are omitted from results even if not yet archived by the dispatcher. Both filters are optional — omit to list everything.

### get_task

Retrieve a single task by full UUID:

```json
{ "task_id": "a7f3d2c1-1234-5678-abcd-000000000000" }
```

Returns the full parsed task as JSON. Returns an error if the UUID is not found.

### update_task

Transition a task's status and append a history entry. The server enforces valid transitions and rejects illegal ones.

```json
{
  "task_id": "a7f3d2c1-1234-5678-abcd-000000000000",
  "new_status": "completed",
  "actor": "claudebox",
  "note": "Stack updated, container healthy, search verified."
}
```

**Allowed transitions:**

| From | To |
|------|----|
| `approved` | `in-progress` |
| `in-progress` | `completed` |
| Any non-terminal | `failed` |

Non-terminal states: `submitted`, `pending-approval`, `approved`, `in-progress`.
Terminal states: `completed`, `failed`.

Transitions not in the table above are rejected with an error. The dispatcher owns the `submitted → approved` and `submitted → pending-approval` transitions; agents own `approved → in-progress → completed`.

**Read-only fields:** `alert_state` and `retry_policy` are managed exclusively by the dispatcher. `update_task` does not expose them — passing either field is ignored, not an error.

## Schema Compatibility

task-queue-mcp writes files that the task-dispatcher reads. Both must agree on the schema. The server serializes all output via `yaml.dump` with default flow style disabled, which produces block-style YAML the dispatcher parses without issue.

Key compatibility constraints:
- `id` is always a UUID4 string (not integer)
- `history` is an append-only list; `update_task` never removes entries
- `alert_state` and `retry_policy` are dispatcher-owned; the MCP server does not touch them
- `context_refs` paths must be absolute — relative paths would be ambiguous on the dispatcher's working directory

If the dispatcher schema ever changes (new required fields, renamed status values), task-queue-mcp needs a coordinated update. The 21 pytest tests cover the full schema surface — run them before deploying changes to either component.

## Runtime

- **PM2-managed Docker container:** `task-queue-mcp`
- **Port:** 8485 (streamable-HTTP)
- **Endpoint:** `http://localhost:8485/mcp`
- **Dependencies:** `fastmcp`, `pyyaml`

Docker security configuration:
```yaml
cap_drop: [ALL]
security_opt: [no-new-privileges:true]
read_only: true
tmpfs: [/tmp]
user: "1000:1000"
volumes:
  - /home/ted/.claude/task-queue:/home/ted/.claude/task-queue  # rw
```

The container runs read-write on the task-queue directory only. The rest of the filesystem is read-only. `/tmp` is a tmpfs mount for any transient scratch space `yaml.dump` needs.

## Configuration

Claude Code `settings.json` (global, all agent sessions):
```json
{
  "task-queue-mcp": {
    "type": "url",
    "url": "http://localhost:8485/mcp"
  }
}
```

## Security Model

Port 8485 is unauthenticated. Any client that can reach it can read and write task files. This follows the same accepted risk pattern as homelab-ops-mcp (port 8282): the port is LAN-only, not proxied externally via SWAG, and the attack surface is limited to the task queue directory.

The container's `cap_drop: ALL` and `no-new-privileges` prevent privilege escalation even if the process is compromised. UID 1000 matches Ted's host user — task files are owned correctly without root involvement.

If MCP server proliferation reaches a point where unauthenticated LAN exposure is a concern, the pattern to adopt is a shared API key header checked in the FastMCP middleware layer — the same pattern used on some homelab services. This has not been needed yet.

## Integration Points

**Task dispatcher** (`~/scripts/task-dispatcher.py`): Reads the same `~/.claude/task-queue/` directory. The MCP server handles writes agents care about (submit, update status); the dispatcher handles routing, approval gating, alerting, and archiving. Both use atomic write (`.tmp → rename`) to prevent race conditions.

**inject-task-queue.sh (SessionStart hook):** Surfaces `approved` and `input-required` tasks to agents at session start. Agents claiming a task via `update_task` (setting `in-progress`) removes it from the hook's next injection — the transition is the acknowledgment.

**task-approve CLI** (`~/bin/task-approve`): Covers the `pending-approval → approved` transition, which the MCP server intentionally does not expose. Approval is a human action.

**NATS JetStream:** The dispatcher publishes task events to NATS; the MCP server does not. If you need event observability on MCP-submitted tasks, the dispatcher's Phase 1 processing is what generates the NATS publish — not the submission itself. There's a ~2-minute window between `submit_task` and the dispatcher picking it up.

## Gotchas

**submit_task always sets status: submitted.** There is no way to inject a task directly at `approved` or any other status via the MCP tools. If you need to bypass the dispatcher's approval routing (e.g., for testing), use the CLI or write the file directly.

**list_tasks TTL filtering is client-side.** TTL-expired tasks are filtered from results but not deleted from disk — that's the dispatcher's Phase 3 job. If you call `get_task` with a known UUID of an expired task, you'll still get it. `list_tasks` just won't surface it proactively.

**UUID validation is strict.** `get_task` and `update_task` reject non-UUID task IDs. Unlike the `task-approve` CLI, there is no prefix matching — pass the full UUID.

**Transition errors are terminal.** `update_task` returns an error for illegal transitions but does not modify the file. The task stays at its current status. Retry with a valid transition, or use the CLI if you need to force a status.

**context_refs paths are validated but not checked for existence.** The server confirms each path is absolute; it does not verify the file exists. A `context_ref` pointing to a non-existent build plan will pass validation and confuse the agent that picks up the task.

## Related Docs

- [Agent Orchestration](agent-orchestration.md) — full task queue overview, lifecycle, and agent manifests
- [Task Dispatcher](task-dispatcher.md) — dispatcher internals, approval routing, retry policy, and alert dedup
- [homelab-ops MCP](homelab-ops-mcp.md) — the companion server for shell and filesystem operations
- [NATS JetStream](nats-jetstream.md) — event bus for task lifecycle observability
