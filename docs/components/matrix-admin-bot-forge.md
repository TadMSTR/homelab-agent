# matrix-admin-bot (forge)

The forge instance of matrix-admin-bot provisions and manages Matrix accounts for forge's
5 operator agents on the `your-forge-domain` homeserver. It is a separate PM2 process
from the claudebox instance — different homeserver, different bot account, different config.

See [matrix-admin-bot.md](matrix-admin-bot.md) for the claudebox instance and full command
reference. This doc covers the forge deployment only.

- **Source:** `~/repos/personal/matrix-admin-bot/`
- **PM2 name:** `matrix-admin-bot-forge` (ID 22)
- **Config:** `~/.secrets/matrix-admin-bot-forge.yml`
- **Status:** online

## How It Runs

```
python bot.py --config /home/ted/.secrets/matrix-admin-bot-forge.yml
```

Launched via the matrix-admin-bot virtualenv at
`~/repos/personal/matrix-admin-bot/venv/bin/python`. Logs at
`~/.pm2/logs/matrix-admin-bot-forge-{out,error}.log`.

## Configuration

Config at `~/.secrets/matrix-admin-bot-forge.yml` (chmod 600). The bot runs as
`@matrix-admin-bot:your-forge-domain` with `@ted:your-forge-domain` as the sole
`allowed_sender`.

5 agent entries configured:
- `sysadmin` — `@agent.sysadmin:your-forge-domain`
- `research` — `@agent.research:your-forge-domain`
- `dev` — `@agent.dev:your-forge-domain`
- `security` — `@agent.security:your-forge-domain`
- `writer` — `@agent.writer:your-forge-domain`

`secrets_dir` points to the forge secrets directory where `!rotate-token` writes new
token files. The `metrics_port` is set to 0 (disabled) on forge.

## Credential Note

At build time, the forge admin bot uses `@ted:your-forge-domain`'s personal tokens
(`access_token` for the bot's Matrix client + `admin_api_token` for Synapse admin calls).
These tokens will expire or become invalid if Ted's personal credentials change on the
forge homeserver. If the bot stops working after a password change, re-provision the bot
with a dedicated service account token.

## Commands

Same command set as the claudebox instance. See [matrix-admin-bot.md](matrix-admin-bot.md)
for the full command reference (`!create-account`, `!rotate-token`, `!audit-memberships`, etc.).

## Related Docs

- [matrix-admin-bot.md](matrix-admin-bot.md) — claudebox instance + full command reference
- [synapse.md](synapse.md) — forge homeserver
- [matrix-mcp-forge.md](matrix-mcp-forge.md) — MCP tool surface for forge agents
