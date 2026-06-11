# task-queue-mcp

task-queue-mcp is a containerized FastMCP server that exposes the forge agent task queue
as an MCP tool surface. Agents submit, retrieve, and update tasks via MCP tool calls;
task state is persisted to JSONL files on disk.

- **Source:** `~/repos/personal/task-queue-mcp`
- **Port:** `127.0.0.1:8485`
- **Queue dir:** `~/.claude/task-queue/` (host-mounted)
- **Network:** `forge-net`

## Container Hardening

```yaml
user: "1000:1000"
cap_drop: [ALL]
security_opt: [no-new-privileges:true]
read_only: true
tmpfs: /tmp
```

The container filesystem is read-only. Only the mounted task queue directory and `/tmp`
are writable. No network ports are exposed to the LAN — only `127.0.0.1:8485`.

## Tool Surface

| Tool | What it does |
|------|-------------|
| `submit_task` | Create a new task with type, payload, and metadata |
| `get_task` | Retrieve a task by ID |
| `list_tasks` | List tasks, optionally filtered by status or type |
| `update_task` | Transition task status and append output notes |

Tasks follow a status lifecycle: `submitted` → `approved` → `in_progress` → `completed`
(or `cancelled` / `input-required`).

## Queue Directory Layout

```
~/.claude/task-queue/
  <task-id>.json     # one file per task
```

Each task file contains the full task record including type, payload, status history, and
output notes. Tasks are never deleted — completed tasks remain as a historical record.

## Scoped-MCP Registration

task-queue-mcp is registered in forge agent manifests that need task coordination:

```yaml
task-queue:
  type: mcp_proxy
  config:
    url: http://localhost:8485/mcp
```

## Related Docs

- [agent-bus.md](agent-bus.md) — event logging alongside task state transitions
- system-agents — agents that consume and update the queue
