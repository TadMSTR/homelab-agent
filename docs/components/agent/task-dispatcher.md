# task-dispatcher

task-dispatcher is a Python script that processes the forge agent task queue every 2 minutes.
It routes tasks between agents, auto-approves low-risk submissions, launches headless agent
sessions, alerts on stale tasks, and archives completed work.

- **Script:** `~/scripts/task-dispatcher.py`
- **Interpreter:** `/usr/bin/python3`
- **Schedule:** PM2 cron, every 2 minutes (`*/2 * * * *`)
- **Log:** `~/.claude/task-queue/dispatcher.log`
- **No listening port** — runs as a batch job, not a server

## How It Works

Each run executes three phases:

1. **Process submitted tasks** — scans `~/.claude/task-queue/*.yml` for `status: submitted`.
   Loads agent manifests to validate target agents. Auto-approves tasks where
   `requires_approval: false`; others are set to `pending-approval` and a Matrix notification
   is sent to Ted. Auto-approved tasks trigger a headless `claude -p` launch for the target agent.

2. **Alert stale approved tasks** — any task in `approved` state for >24 hours triggers a
   Matrix notification to `#forge:helmforge.me`. Re-alerts every 24 hours until claimed.

3. **Archive expired tasks** — moves `completed` or `failed` tasks past their `ttl_days`
   into `~/.claude/task-queue/archive/`.

## Headless Agent Launch

When a task is auto-approved, the dispatcher launches the target agent headlessly:

```bash
claude -p --dangerously-skip-permissions \
  "You have a pending task (id=<task_id>). Check your task queue and proceed."
```

The launch runs in the agent's project directory from a hardcoded whitelist:

| Agent | Project dir |
|-------|-------------|
| sysadmin | `~/.claude/projects/sysadmin` |
| developer | `~/.claude/projects/developer` |
| research | `~/.claude/projects/research` |
| writer | `~/.claude/projects/writer` |
| security | `~/.claude/projects/security` |

Launch logs go to `~/.pm2/logs/agent-launch-<agent>-<task_id_prefix>.log`.

## Configuration

| Setting | Value |
|---------|-------|
| Task queue dir | `~/.claude/task-queue/` |
| Manifest dir | `~/.claude/manifests/` |
| Matrix MCP URL | `http://127.0.0.1:8487/mcp` |
| Retry backoff | 3 retries: 5m, 10m, 20m |
| Stale alert threshold | 24 hours |
| Re-alert interval | 24 hours |
| Dead letter dir | `~/.claude/task-queue/dead-letters/` |

## Dependencies

- **task-queue-mcp** (port 8485) — provides the task YAML files on disk
- **matrix-mcp** (port 8487) — sends notifications to Matrix
- **agent-bus** — event logging via `agent_bus_client.log_event()`
- **Agent manifests** — `~/.claude/manifests/*.yaml` for routing validation

## Operations

```bash
# Check status
pm2 show task-dispatcher

# View recent logs
tail -50 ~/.claude/task-queue/dispatcher.log

# Force a run
pm2 restart task-dispatcher

# Check for dead-lettered tasks
ls ~/.claude/task-queue/dead-letters/

# Check for stale approved tasks
grep -l "status: approved" ~/.claude/task-queue/*.yml
```

## Related Docs

- [task-queue-mcp.md](task-queue-mcp.md) — the MCP server that manages task state
- [agent-bus.md](agent-bus.md) — event bus for agent coordination
- system-agents — agents dispatched by this service
