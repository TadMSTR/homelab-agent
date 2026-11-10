# matrix-task-queue-bot (retired 2026-10-29)

matrix-task-queue-bot was a Matrix bot for task queue management on forge. It provided text
commands, headless session launching, and inotify-based status notifications in Matrix
rooms.

## Retirement

Retired 2026-10-29 by the `matrix-notify-overhaul-2026-10` p1 build ("quiet down").

**Why:** Matrix is now notify-only. Nobody replies to agents from the phone, so
[matrix-dispatcher](matrix-dispatcher.md), which turned Matrix messages into agent actions,
was retired. This bot and [matrix-admin-bot](matrix-admin-bot.md) were retired with it.

**What was removed:**

- the PM2 process (`pm2 delete`, then `pm2 save`). It was never defined in an
  `ecosystem.config.js`, so there was no start file to remove;
- the bot's Matrix devices, which were revoked.

The pinned per-agent boards and the daily morning brief described below no longer update.
[task-queue-mcp](task-queue-mcp.md) itself is unaffected. The full record is in the
`matrix-notify-overhaul-2026-10` p1 build record (private).

The rest of this doc describes the bot as it ran before retirement, for reference.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `matrix-task-queue-bot` |
| Type | always-on |
| Script | `~/repos/personal/matrix-task-queue-bot/venv/bin/python` |
| Args | `-m src.bot` |
| CWD | `~/repos/personal/matrix-task-queue-bot/` |
| Port | — (no listener, connected to the Matrix homeserver as a client) |

## How It Worked

Three concurrent subsystems:

1. **Text command handler** — responded to `!queue`, `!task`, `!help` commands in the `#task-queue` Matrix room
2. **Widget event handler** — processed the custom room event types the task-queue-widget sent for task actions. The widget was retired 2026-10-25, after which nothing sent these events and the handler was dormant
3. **File watcher** — monitored `~/.claude/task-queue/` via inotify for task file changes and
   drove the pinned per-agent boards and the daily morning brief (see below)

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

The room was a passive status surface, not a notification firehose. Per-task Matrix
messages on every status transition had been removed in favor of two mechanisms:

1. **Pinned per-agent boards** — one pinned, self-editing board per agent (default set:
   `developer`, `sysadmin`, `research`, `writer`, `security`, configurable via `BOARD_AGENTS`).
   Each board listed that agent's non-terminal tasks only, with columns
   ID / Priority / Status / Type / Summary / Age. Boards were edited silently in place via
   Matrix `m.replace` on every task event — no ping — and pinned to the room via
   `m.room.pinned_events` (the bot held power level 50 to manage pins). State persisted at
   `~/.local/state/matrix-task-queue-bot/boards.json`.

2. **Morning brief** — exactly one notifying message per day: a dated, fresh post at
   05:00 local time summarizing queue state, de-duplicated via a digest-stamp so restarts
   didn't re-send the same day's brief.

Workflow mode tags also appeared on a task when it transitioned to `approved`:

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
- **Python deps:** matrix-nio, httpx, watchdog, pyyaml, python-dotenv

## Operations (historical)

These commands applied while the bot ran. The PM2 process no longer exists.

```bash
# Check status
pm2 show matrix-task-queue-bot

# View logs
pm2 logs matrix-task-queue-bot --lines 30

# Restart
pm2 restart matrix-task-queue-bot
```

## Related Docs

- [task-queue-widget.md](task-queue-widget.md) — former web widget UI (retired 2026-10-25)
- [task-queue-mcp.md](task-queue-mcp.md) — MCP server for task queue
- [task-dispatcher.md](task-dispatcher.md) — dispatcher that processes tasks
- [matrix-dispatcher.md](matrix-dispatcher.md) — Matrix message router (retired 2026-10-29)
