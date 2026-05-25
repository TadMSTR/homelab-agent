# matrix-admin-bot

matrix-admin-bot is a Matrix chatbot for administering a Synapse homeserver. It runs in
a dedicated admin room, accepts commands only from an allowlisted set of senders, and
exposes Synapse's admin API as chat commands — account creation, token rotation, room
membership auditing, and lockout/restore.

On claudebox it manages the agent Matrix accounts: provisioning credentials, rotating
access tokens, and verifying room membership against each agent's configured allowlist.

- **Source:** `~/repos/personal/matrix-admin-bot/`
- **Public repo:** [TadMSTR/matrix-admin-bot](https://github.com/TadMSTR/matrix-admin-bot)
- **Process:** PM2 (ID 29, `matrix-admin-bot`, `online`)
- **Config:** `/home/ted/.claude-secrets/matrix-admin-bot.yml`
- **Logs:** `~/.claude/logs/matrix-admin-bot-{out,error}.log`

## Commands

| Command | Description |
|---------|-------------|
| `!create-account @user:domain [displayname]` | Create or update a Synapse user account |
| `!join-room @user:domain !room:domain` | Force-join a user into a room (per-agent allowlist enforced) |
| `!list-rooms @user:domain` | List all rooms a user is joined to |
| `!audit-memberships` | Compare every agent's actual room membership against its configured `allowed_rooms` |
| `!revoke-token @user:domain` | Lock a user account (reversible) |
| `!restore-token @user:domain` | Unlock a previously locked account |
| `!rotate-token @user:domain` | Rotate access token and write new token to `secrets_dir` |
| `!status` | Show bot uptime, homeserver URL, and agent count |

## Configuration

Config lives at `/home/ted/.claude-secrets/matrix-admin-bot.yml` (chmod 600). Key fields:

```yaml
homeserver: https://matrix.your-homeserver-domain
bot_user_id: "@matrix-admin-bot:your-homeserver-domain"
access_token: "<bot access token>"
admin_api_token: "<Synapse admin token>"   # for /_synapse/admin/*
admin_room_id: "!<room>:domain"            # commands accepted here
notification_room_id: "!<room>:domain"     # write-only status room

allowed_senders:
  - "@ted:your-homeserver-domain"

agents:
  research:
    mxid: "@agent.research:your-homeserver-domain"
    device_id: ""
    allowed_rooms:
      - "!<room>:domain"

secrets_dir: "/home/ted/.claude-secrets"   # where !rotate-token writes token files
log_level: "INFO"                          # DEBUG, INFO, WARNING, ERROR
metrics_port: 9092                         # 0 = disabled; binds 127.0.0.1 only
```

The bot derives its homeserver domain from `bot_user_id`, not from the `homeserver` URL.
This supports Synapse deployments where the homeserver URL and the Matrix server name
differ (e.g. `matrix.example.com` serving MXIDs on `:example.com`).

## Prometheus Metrics

When `metrics_port` is non-zero, the bot exposes `/metrics` on `127.0.0.1:<metrics_port>`.
The endpoint is unauthenticated — binding to loopback only prevents LAN exposure.

| Metric | Type | Description |
|--------|------|-------------|
| `matrix_admin_bot_commands_total` | Counter | Commands handled, labelled by `command` and `status` |
| `matrix_admin_bot_command_errors_total` | Counter | Failed commands, labelled by `command` |
| `matrix_admin_bot_command_duration_seconds` | Histogram | End-to-end command latency |
| `matrix_admin_bot_synapse_duration_seconds` | Histogram | Synapse API call latency |

## Structured Logging

The bot uses `structlog` with `contextvars` for correlation IDs. Each command dispatch
binds a `correlation_id` to the context so all log lines for a single command execution
carry the same ID — useful for tracing multi-step commands like `!rotate-token` through
the logs when errors occur partway through.

## Notification Room Policy

`notification_room_id` is write-only. The bot sends status messages there (e.g. startup
notifications, audit summaries) but does not accept commands from that room. Commands are
only processed from `admin_room_id`. This prevents the notification room from being used
as an accidental command channel.

## Token Rotation (`!rotate-token`)

`!rotate-token` is a multi-step operation: it deletes the old device, creates a new one,
and writes the new token to `<secrets_dir>/<agent_id>.token` atomically with `0o600`
permissions. If the operation fails after step 1 (device deleted), the error message
includes lockout recovery guidance — the agent is locked out and needs re-provisioning
via `!create-account` or direct Synapse admin intervention.

## Security

From audit 2026-05-24 (first formal audit of the public repo):

| Finding | Status |
|---------|--------|
| M1: Internal hostnames/MXIDs/paths in git history (public repo) | Fixed — history squashed via `git commit-tree`; 6 stale remote branches deleted; force-pushed |
| L1: `!rotate-token` gave no lockout recovery guidance on partial failure | Fixed — step-aware error message (commit `c9e3949`) |
| L2: `_check()` included raw Synapse error body in Matrix messages | Fixed — extracted `errcode`/`error` JSON fields only (commit `10244d6`) |

Security design properties confirmed clean at audit:
- Authorization is by sender identity only — room membership is not treated as authorization
- MXID and room ID inputs are regex-validated against the homeserver domain before any Synapse API call
- `!join-room` enforces a per-agent `allowed_rooms` allowlist; joins to undeclared rooms are refused
- Admin API token and login tokens are never logged
- Prometheus metrics bind `127.0.0.1` only

## PM2 Setup

```bash
# Currently running as:
venv/bin/python3 bot.py --config /home/ted/.claude-secrets/matrix-admin-bot.yml

# To restart after config changes:
pm2 restart matrix-admin-bot
```

`SIGTERM` is handled gracefully — in-flight multi-step commands complete before shutdown.
PM2's `kill_timeout` should be at least 5000 ms.
