# matrix-dispatcher (forge)

The forge instance of matrix-dispatcher routes operator Matrix messages to the correct
forge agent Claude Code session. It polls the forge homeserver for new messages in each
agent's room and injects them into the agent's Claude Code project directory.

- **Source:** `~/repos/personal/matrix-dispatcher/`
- **PM2 name:** `matrix-dispatcher` (ID 21)
- **Entry point:** `start-forge.sh`
- **Status:** online

## How It Runs

`start-forge.sh` sources credentials from `/home/ted/.secrets/matrix-dispatcher.env`
(bot access token), then executes `dispatcher.py`. The credentials file must exist and be
readable before the process starts — PM2 restarts will fail with an error if it's missing.

Logs at `~/.pm2/logs/matrix-dispatcher-{out,error}.log`.

## Configuration

Config at `~/repos/personal/matrix-dispatcher/config.yml`:

```yaml
homeserver: "https://matrix.helmforge.me"
access_token_env: "DISPATCHER_ACCESS_TOKEN"
bot_user_id: "@forge-sysadmin:helmforge.me"
trusted_sender: "@ted:helmforge.me"
mention_user: "@ted:helmforge.me"
poll_interval_seconds: 5
max_message_length: 4000
session_retention_days: 30
startup_notification_agent: sysadmin

agents:
  sysadmin:
    room_id: "!<room>:helmforge.me"
    project_dir: "/home/ted/.claude/projects/sysadmin"
  research:
    room_id: "!<room>:helmforge.me"
    project_dir: "/home/ted/.claude/projects/research"
  developer:
    room_id: "!<room>:helmforge.me"
    project_dir: "/home/ted/.claude/projects/developer"
  security:
    room_id: "!<room>:helmforge.me"
    project_dir: "/home/ted/.claude/projects/security"
  writer:
    room_id: "!<room>:helmforge.me"
    project_dir: "/home/ted/.claude/projects/writer"
```

The dispatcher bot runs as `@forge-sysadmin:helmforge.me`. Only messages from
`trusted_sender` (`@ted:helmforge.me`) are routed to agent sessions — other senders
are ignored.

`startup_notification_agent: sysadmin` means the sysadmin agent's room receives a message
when the dispatcher starts or restarts.

## Agent Routing

When a message arrives in an agent room from `trusted_sender`, the dispatcher writes it
to the agent's project directory (`project_dir`) where Claude Code picks it up as input.
The `project_dir` paths map to the standard forge Claude Code project directories.

## Relationship to Forge-Agent-Setup

The `project_dir` values require each forge agent's Claude Code project to exist at the
configured path. These were provisioned by the `forge-agent-setup` build (completed
2026-05-25). The `forge-matrix-agent-wiring` build (completed 2026-05-25) updated
`config.yml` with all 5 real paths and corrected the agent key name from `dev` to
`developer`. The dispatcher is fully wired and routing live agent sessions.

## Related Docs

- [synapse.md](synapse.md) — forge homeserver
- [matrix-mcp.md](matrix-mcp.md) — MCP tool surface for forge agents
- [matrix-admin-bot.md](matrix-admin-bot.md) — account management bot
