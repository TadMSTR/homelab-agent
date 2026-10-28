# matrix-admin-bot (forge)

The forge instance of matrix-admin-bot provisions and manages Matrix accounts for forge's
5 operator agents on the `example.com` homeserver. It is a separate PM2 process
from the claudebox instance — different homeserver, different bot account, different config.

See homelab-agent matrix-admin-bot doc
for the claudebox instance and full command reference. This doc covers the forge deployment only.

- **Source:** `~/repos/personal/matrix-admin-bot/`
- **PM2 name:** `matrix-admin-bot-forge` (ID 4)
- **Config:** `~/.secrets/matrix-admin-bot.yml`
- **Status:** online

## How It Runs

```
python bot.py --config ~/.secrets/matrix-admin-bot.yml
```

Launched via the matrix-admin-bot virtualenv at
`~/repos/personal/matrix-admin-bot/venv/bin/python`. Logs at
`~/.pm2/logs/matrix-admin-bot-forge-{out,error}.log`.

## Configuration

Config at `~/.secrets/matrix-admin-bot.yml` (chmod 600). The bot runs as
`@matrix-admin-bot:example.com` with `@ted:example.com` as the sole
`allowed_sender`.

5 agent entries configured:
- `sysadmin` — `@agent.sysadmin:example.com`
- `research` — `@agent.research:example.com`
- `dev` — `@agent.dev:example.com`
- `security` — `@agent.security:example.com`
- `writer` — `@agent.writer:example.com`

`secrets_dir` points to the forge secrets directory where `!rotate-token` writes new
token files. The `metrics_port` is set to 0 (disabled) on forge.

## Credential Note

At build time, the forge admin bot uses `@ted:example.com`'s personal tokens
(`access_token` for the bot's Matrix client + `admin_api_token` for Synapse admin calls).
These tokens will expire or become invalid if Ted's personal credentials change on the
forge homeserver. If the bot stops working after a password change, re-provision the bot
with a dedicated service account token.

## Commands

Same command set as the claudebox instance. See homelab-agent matrix-admin-bot doc
for the full command reference (`!create-account`, `!rotate-token`, `!audit-memberships`, etc.).

## Related Docs

- [synapse.md](synapse.md) — forge homeserver
- [matrix-mcp.md](matrix-mcp.md) — MCP tool surface for forge agents
- [matrix-dispatcher.md](matrix-dispatcher.md) — message routing to forge agents
