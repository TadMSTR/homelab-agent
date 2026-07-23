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
3. **File watcher** — monitors `~/.claude/task-queue/` via inotify for task file changes and
   drives the pinned per-agent boards and the daily morning brief (see below)

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

## Status Board

The room is a passive status surface, not a notification firehose. Per-task Matrix
messages on every status transition were removed in favor of two mechanisms:

1. **Pinned per-agent boards** — one pinned, self-editing board per agent (default set:
   `developer`, `sysadmin`, `research`, `writer`, `security`, configurable via `BOARD_AGENTS`).
   Each board lists that agent's non-terminal tasks only, with columns
   ID / Priority / Status / Type / Summary / Age. Boards are edited silently in place via
   Matrix `m.replace` on every task event — no ping — and pinned to the room via
   `m.room.pinned_events` (the bot holds power level 50 to manage pins). State persists at
   `~/.local/state/matrix-task-queue-bot/boards.json`.

2. **Morning brief** — exactly one notifying message per day: a dated, fresh post at
   05:00 local time summarizing queue state, de-duplicated via a digest-stamp so restarts
   don't re-send the same day's brief.

Workflow mode tags still appear on a task when it transitions to `approved`:

- `[semi-auto]` — awaiting operator pickup; shows resume instructions
- `[auto]` — dispatcher will auto-launch the target agent

## Configuration

| Env Var | Purpose |
|---------|---------|
| MATRIX_HOMESERVER_URL | Synapse homeserver URL |
| MATRIX_ROOM_TASK_QUEUE | Room for task queue messages |
| TASK_QUEUE_DIR | `~/.claude/task-queue/` |
| STATE_DIR | Directory for board/digest state (default `~/.local/state/matrix-task-queue-bot/`) |
| DIGEST_HOUR | Local hour (0-23) the daily morning brief posts, default 5 |
| BOARD_COALESCE_SEC | Debounce window for board edits when multiple task events land close together |
| BOARD_AGENTS | Comma-separated agent list to maintain pinned boards for (default `developer,sysadmin,research,writer,security`) |
| MAX_BOARD_AGENTS | Upper bound on the number of pinned boards the bot will maintain at once |

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
