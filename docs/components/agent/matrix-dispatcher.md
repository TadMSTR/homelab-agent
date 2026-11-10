# matrix-dispatcher (forge) (retired 2026-10-29)

The forge instance of matrix-dispatcher routed operator Matrix messages to the correct
forge agent Claude Code session. It polled the forge homeserver for new messages in each
agent's room and injected them into the agent's Claude Code project directory.

## Retirement

Retired 2026-10-29 by the `matrix-notify-overhaul-2026-10` p1 build ("quiet down").

**Why:** Matrix is now notify-only. Nobody replies to agents from the phone, so a service
that turned Matrix messages into agent actions had no remaining job.
[matrix-task-queue-bot](matrix-task-queue-bot.md) and
[matrix-admin-bot](matrix-admin-bot.md) were retired with it.

**What was removed:**

- the PM2 process (`pm2 delete`, then `pm2 save`). It was never defined in an
  `ecosystem.config.js`, so there was no start file to remove;
- the bot's Matrix devices, which were revoked.

[matrix-mcp](matrix-mcp.md), which agents use to send messages, is unaffected and still
runs. The full record is in the `matrix-notify-overhaul-2026-10` p1 build record (private).

The rest of this doc describes the dispatcher as it ran before retirement, for reference.

## What it was

- **Source:** `~/repos/personal/matrix-dispatcher/`
- **PM2 name:** `matrix-dispatcher-forge`
- **Entry point:** `start-forge.sh`

## How It Ran

`start-forge.sh` sourced credentials from `~/.secrets/matrix-dispatcher.env`
(bot access token), then executed `dispatcher.py`. The credentials file had to exist and be
readable before the process started; PM2 restarts failed with an error if it was missing.

Logs were at `~/.pm2/logs/matrix-dispatcher-forge-{out,error}.log`.

## Configuration

Config at `~/repos/personal/matrix-dispatcher/config.yml`:

```yaml
homeserver: "https://matrix.example.com"
access_token_env: "DISPATCHER_ACCESS_TOKEN"
bot_user_id: "@forge-sysadmin:example.com"
trusted_sender: "@ted:example.com"
mention_user: "@ted:example.com"
poll_interval_seconds: 5
max_message_length: 4000
session_retention_days: 30
startup_notification_agent: sysadmin

agents:
  sysadmin:
    room_id: "!<room>:example.com"
    project_dir: "~/.claude/projects/sysadmin"
  research:
    room_id: "!<room>:example.com"
    project_dir: "~/.claude/projects/research"
  developer:
    room_id: "!<room>:example.com"
    project_dir: "~/.claude/projects/developer"
  security:
    room_id: "!<room>:example.com"
    project_dir: "~/.claude/projects/security"
  writer:
    room_id: "!<room>:example.com"
    project_dir: "~/.claude/projects/writer"
```

The dispatcher bot ran as `@forge-sysadmin:example.com`. Only messages from
`trusted_sender` (`@ted:example.com`) were routed to agent sessions; other senders
were ignored.

`startup_notification_agent: sysadmin` meant the sysadmin agent's room received a message
when the dispatcher started or restarted.

## Agent Routing

When a message arrived in an agent room from `trusted_sender`, the dispatcher wrote it
to the agent's project directory (`project_dir`) where Claude Code picked it up as input.
The `project_dir` paths mapped to the standard forge Claude Code project directories.

## Relationship to Forge-Agent-Setup

The `project_dir` values required each forge agent's Claude Code project to exist at the
configured path. These were provisioned by the `forge-agent-setup` build (completed
2026-05-25). The `forge-matrix-agent-wiring` build (completed 2026-05-25) updated
`config.yml` with all 5 real paths and corrected the agent key name from `dev` to
`developer`. From then until its retirement, the dispatcher routed live agent sessions.

## Related Docs

- [synapse.md](synapse.md) — forge homeserver
- [matrix-mcp.md](matrix-mcp.md) — MCP tool surface for forge agents (still running)
- [matrix-admin-bot.md](matrix-admin-bot.md) — account management bot (retired 2026-10-29)
- [matrix-task-queue-bot.md](matrix-task-queue-bot.md) — task queue bot (retired 2026-10-29)
