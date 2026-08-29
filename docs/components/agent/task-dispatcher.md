# task-dispatcher

task-dispatcher is a Python script that processes the forge agent task queue every 2 minutes.
It routes tasks between agents, auto-approves low-risk submissions, launches headless agent
sessions, alerts on stale tasks, and archives completed work.

- **Script:** `~/scripts/task-dispatcher.py`
- **Interpreter:** `/usr/bin/python3`
- **Schedule:** PM2 cron, every 2 minutes (`*/2 * * * *`)
- **Log:** `~/.pm2/logs/task-dispatcher-out.log` (stderr: `task-dispatcher-error.log`)
- **No listening port** — runs as a batch job, not a server

## How It Works

Each run executes two phases:

1. **Process submitted tasks** — scans `~/.claude/task-queue/*.yml` for `status: submitted`.
   Loads agent manifests to validate target agents. Auto-approves tasks where
   `requires_approval: false`; others are set to `pending-approval` and a Matrix notification
   is sent to Ted. Auto-approved tasks trigger a headless `claude -p` launch for the target agent.

2. **Archive expired tasks** — moves `completed` or `failed` tasks past their `ttl_days`
   into `~/.claude/task-queue/archive/`.

Per-task stale-approval alerting (a Matrix notification to the `alerts` room for any task
`approved` >24h) was removed — it was a notification firehose. Status visibility for
non-terminal tasks now comes from the matrix-task-queue-bot's per-agent pinned board (see
[matrix-task-queue-bot.md](matrix-task-queue-bot.md)) instead of per-task dispatcher alerts.

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

Headless launches authenticate from the target agent's environment, trying
`ANTHROPIC_API_KEY`, then `ANTHROPIC_AUTH_TOKEN`, then `CLAUDE_CODE_OAUTH_TOKEN`
(any one is sufficient), and falling back to `~/.claude/.credentials.json` as a last
resort. If none yields a usable credential, the dispatcher refuses the launch and routes
the task to failure rather than starting a session that would immediately error on an
expired or missing token.

## Logging

Logs go to `~/.pm2/logs/task-dispatcher-out.log` (stderr to `task-dispatcher-error.log`) —
cron's own stdout/stderr redirect is the only sink. A prior duplicate `FileHandler` also
writing `~/.claude/task-queue/dispatcher.log` was removed in v1.1.0; that file is not
deleted automatically and stops growing once the change is deployed.

Each tick emits one INFO line, not three — the run-start banner and the manifest-load
detail dropped to DEBUG. `=== task-dispatcher run complete ===` stays at INFO with that
exact wording: a Loki `absent_over_time` cron-liveness alert may key on the string, so
treat it as a contract, not incidental log text.

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
tail -50 ~/.pm2/logs/task-dispatcher-out.log

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
