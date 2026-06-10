# matrix-task-queue-bot

Matrix bot for task queue management on forge. Provides text commands, widget event
handling, headless session launching, and inotify-based status notifications in Matrix
rooms.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `matrix-task-queue-bot` |
| Type | always-on |
| Script | `~/repos/personal/matrix-task-queue-bot/venv/bin/python` |
| Args | `-m src.bot` |
| CWD | `~/repos/personal/matrix-task-queue-bot/` |
| Port | — (no listener, connects to Matrix homeserver as client) |

## How It Works

Three concurrent subsystems:

1. **Text command handler** — responds to `!queue`, `!task`, `!help` commands in the `#task-queue` Matrix room
2. **Widget event handler** — processes custom helmforge event types from the task-queue-widget for task actions
3. **File watcher** — monitors `~/.claude/task-queue/` via inotify for task file changes, sends status notifications to Matrix

## Text Commands

| Command | Description |
|---------|-------------|
| `!queue` | List all tasks |
| `!queue <agent>` | Filter tasks by agent |
| `!task <id>` | Show task detail with history |
| `!task start <id>` | Launch session in review mode |
| `!task run <id>` | Launch session in auto mode |
| `!task approve <id>` | Approve a pending task |
| `!help` | Show command help |

## Status Notifications

When a task transitions to `approved`, the bot includes a workflow mode tag:

- `[semi-auto]` — awaiting operator pickup; shows resume instructions
- `[auto]` — dispatcher will auto-launch the target agent

## Configuration

| Env Var | Purpose |
|---------|---------|
| MATRIX_HOMESERVER_URL | Synapse homeserver URL |
| MATRIX_ROOM_TASK_QUEUE | Room for task queue messages |
| TASK_QUEUE_DIR | `~/.claude/task-queue/` |

## Dependencies

- **Synapse** — Matrix homeserver
- **task-queue-mcp** — task queue data (YAML files in `~/.claude/task-queue/`)
- **task-queue-widget** — optional web UI communicating via room events
- **Python deps:** matrix-nio, httpx, watchdog, pyyaml, python-dotenv

## Operations

```bash
# Check status
pm2 show matrix-task-queue-bot

# View logs
pm2 logs matrix-task-queue-bot --lines 30

# Restart
pm2 restart matrix-task-queue-bot
```

## Related Docs

- [task-queue-widget.md](task-queue-widget.md) — web widget UI
- [task-queue-mcp.md](task-queue-mcp.md) — MCP server for task queue
- [task-dispatcher.md](task-dispatcher.md) — dispatcher that processes tasks
