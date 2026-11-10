# matrix-admin-bot (forge) (retired 2026-10-29)

The forge instance of matrix-admin-bot provisioned and managed Matrix accounts for forge's
5 operator agents on the `example.com` homeserver. It was a separate PM2 process
from the claudebox instance — different homeserver, different bot account, different config.

See homelab-agent matrix-admin-bot doc
for the claudebox instance and full command reference. This doc covers the forge deployment only.

## Retirement

Retired 2026-10-29 by the `matrix-notify-overhaul-2026-10` p1 build ("quiet down").

**Why:** Matrix is now notify-only. Nobody replies to agents from the phone, so
[matrix-dispatcher](matrix-dispatcher.md), which turned Matrix messages into agent actions,
was retired. This bot and [matrix-task-queue-bot](matrix-task-queue-bot.md) were retired
with it.

**What was removed:**

- the PM2 process (`pm2 delete`, then `pm2 save`). It was never defined in an
  `ecosystem.config.js`, so there was no start file to remove;
- the bot's Matrix devices, which were revoked.

[matrix-mcp](matrix-mcp.md), which agents use to send messages, is unaffected and still
runs. The full record is in the `matrix-notify-overhaul-2026-10` p1 build record (private).

The rest of this doc describes the forge bot as it ran before retirement, for reference.

## What it was

- **Source:** `~/repos/personal/matrix-admin-bot/`
- **PM2 name:** `matrix-admin-bot-forge`
- **Config:** `~/.secrets/matrix-admin-bot.yml`

## How It Ran

```
python bot.py --config ~/.secrets/matrix-admin-bot.yml
```

Launched via the matrix-admin-bot virtualenv at
`~/repos/personal/matrix-admin-bot/venv/bin/python`. Logs were at
`~/.pm2/logs/matrix-admin-bot-forge-{out,error}.log`.

## Configuration

Config at `~/.secrets/matrix-admin-bot.yml` (chmod 600). The bot ran as
`@matrix-admin-bot:example.com` with `@ted:example.com` as the sole
`allowed_sender`.

5 agent entries were configured:
- `sysadmin` — `@agent.sysadmin:example.com`
- `research` — `@agent.research:example.com`
- `dev` — `@agent.dev:example.com`
- `security` — `@agent.security:example.com`
- `writer` — `@agent.writer:example.com`

`secrets_dir` pointed to the forge secrets directory where `!rotate-token` wrote new
token files. The `metrics_port` was set to 0 (disabled) on forge.

## Credential Note

At build time, the forge admin bot used `@ted:example.com`'s personal tokens
(`access_token` for the bot's Matrix client + `admin_api_token` for Synapse admin calls),
not a dedicated service account. Those tokens would have expired or become invalid if Ted's
personal credentials changed on the forge homeserver.

## Commands

Same command set as the claudebox instance. See homelab-agent matrix-admin-bot doc
for the full command reference (`!create-account`, `!rotate-token`, `!audit-memberships`, etc.).

## Related Docs

- [synapse.md](synapse.md) — forge homeserver
- [matrix-mcp.md](matrix-mcp.md) — MCP tool surface for forge agents (still running)
- [matrix-dispatcher.md](matrix-dispatcher.md) — message routing to forge agents (retired 2026-10-29)
