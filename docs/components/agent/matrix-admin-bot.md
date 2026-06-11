# matrix-admin-bot (forge)

The forge instance of matrix-admin-bot provisions and manages Matrix accounts for forge's
5 operator agents on the `helmforge.me` homeserver. It is a separate PM2 process
from the claudebox instance — different homeserver, different bot account, different config.

See homelab-agent matrix-admin-bot doc
for the claudebox instance and full command reference. This doc covers the forge deployment only.

- **Source:** `~/repos/personal/matrix-admin-bot/`
- **PM2 name:** `matrix-admin-bot` (ID 22)
- **Config:** `~/.secrets/matrix-admin-bot.yml`
- **Status:** online

## How It Runs

```
python bot.py --config /home/ted/.secrets/matrix-admin-bot.yml
```

Launched via the matrix-admin-bot virtualenv at
`~/repos/personal/matrix-admin-bot/venv/bin/python`. Logs at
`~/.pm2/logs/matrix-admin-bot-{out,error}.log`.

## Configuration

Config at `~/.secrets/matrix-admin-bot.yml` (chmod 600). The bot runs as
`@matrix-admin-bot:helmforge.me` with `@ted:helmforge.me` as the sole
`allowed_sender`.

5 agent entries configured:
- `sysadmin` — `@agent.sysadmin:helmforge.me`
- `research` — `@agent.research:helmforge.me`
- `dev` — `@agent.dev:helmforge.me`
- `security` — `@agent.security:helmforge.me`
- `writer` — `@agent.writer:helmforge.me`

`secrets_dir` points to the forge secrets directory where `!rotate-token` writes new
token files. The `metrics_port` is set to 0 (disabled) on forge.

## Credential Note

At build time, the forge admin bot uses `@ted:helmforge.me`'s personal tokens
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
