# matrix-dispatcher (forge)

The forge instance of matrix-dispatcher routes operator Matrix messages to the correct
forge agent Claude Code session. It polls the forge homeserver for new messages in each
agent's room and injects them into the agent's Claude Code project directory.

See [matrix-dispatcher.md](matrix-dispatcher.md) for the claudebox instance. This doc
covers the forge deployment only.

- **Source:** `~/repos/personal/matrix-dispatcher/`
- **PM2 name:** `matrix-dispatcher-forge` (ID 21)
- **Entry point:** `start-forge.sh`
- **Status:** online

## How It Runs

`start-forge.sh` sources credentials from `/home/ted/.secrets/matrix-dispatcher-forge.env`
(bot access token), then executes `dispatcher.py`. The credentials file must exist and be
readable before the process starts — PM2 restarts will fail with an error if it's missing.

Logs at `~/.pm2/logs/matrix-dispatcher-forge-{out,error}.log`.

## Configuration

Config at `~/repos/personal/matrix-dispatcher/config.yml`:

```yaml
homeserver: "https://matrix.your-forge-domain"
access_token_env: "DISPATCHER_ACCESS_TOKEN"
bot_user_id: "@forge-sysadmin:your-forge-domain"
trusted_sender: "@ted:your-forge-domain"
mention_user: "@ted:your-forge-domain"
poll_interval_seconds: 5
max_message_length: 4000
session_retention_days: 30
startup_notification_agent: sysadmin

agents:
  sysadmin:
    room_id: "!<room>:your-forge-domain"
    project_dir: "/home/ted/.claude/projects/sysadmin"
  research:
    room_id: "!<room>:your-forge-domain"
    project_dir: "/home/ted/.claude/projects/research"
  dev:
    room_id: "!<room>:your-forge-domain"
    project_dir: "/home/ted/.claude/projects/dev"
  security:
    room_id: "!<room>:your-forge-domain"
    project_dir: "/home/ted/.claude/projects/security"
  writer:
    room_id: "!<room>:your-forge-domain"
    project_dir: "/home/ted/.claude/projects/writer"
```

The dispatcher bot runs as `@forge-sysadmin:your-forge-domain`. Only messages from
`trusted_sender` (`@ted:your-forge-domain`) are routed to agent sessions — other senders
are ignored.

`startup_notification_agent: sysadmin` means the sysadmin agent's room receives a message
when the dispatcher starts or restarts.

## Agent Routing

When a message arrives in an agent room from `trusted_sender`, the dispatcher writes it
to the agent's project directory (`project_dir`) where Claude Code picks it up as input.
The `project_dir` paths map to the standard forge Claude Code project directories.

## Relationship to Forge-Agent-Setup

The `project_dir` values require each forge agent's Claude Code project to exist at the
configured path. These are provisioned by the `forge-agent-setup` build — if that build
hasn't run for an agent, messages will be written to a path with no active session.

## Related Docs

- [matrix-dispatcher.md](matrix-dispatcher.md) — claudebox instance
- [synapse.md](synapse.md) — forge homeserver
- [matrix-mcp-forge.md](matrix-mcp-forge.md) — MCP tool surface for forge agents
