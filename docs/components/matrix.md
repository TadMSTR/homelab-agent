# Matrix Agent Communications

Synapse-based Matrix homeserver plus two dedicated tools — `matrix-mcp` (FastMCP HTTP server) and `matrix-channel` (Claude Code Channel plugin) — that give every agent in the system two-way messaging with the operator. Deployed as the primary agent notification and communication layer, replacing ntfy for most events.

## Why It Exists

Before Matrix, agents sent ntfy push notifications for status updates and blocked tasks. ntfy is fire-and-forget: no threading, no history, no way for the agent to read prior messages in a conversation. The Matrix stack adds:

- **Persistent history** per agent room — missed notifications don't disappear
- **Two-way interaction** — operator messages route back to the agent session via matrix-channel
- **Structured artifact posting** — agents post files, logs, and reports directly to Matrix rooms
- **Unified inbox** — all agent activity visible in Element Web without a separate app

ntfy is retained for two cases: pending-approval notifications (where the operator needs to act before the agent can continue) and dead-letter events (task queue failures, stale handoffs). Everything else routes to Matrix.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Agent session (Claude Code)                        │
│  mcp__matrix__send_matrix_message                   │
│  mcp__matrix__post_artifact                         │
│  mcp__matrix__get_matrix_messages                   │
└──────────────────┬──────────────────────────────────┘
                   │ HTTP (127.0.0.1:8487)
                   ▼
┌─────────────────────────────────────────────────────┐
│  matrix-mcp (FastMCP, PM2, port 8487)               │
│  - send_matrix_message: text + markdown formatting  │
│  - post_artifact: file → Matrix media upload        │
│  - get_matrix_messages: read room history           │
│  - list_matrix_rooms: enumerate joined rooms        │
└──────────────────┬──────────────────────────────────┘
                   │ Matrix client API (HTTPS)
                   ▼
┌─────────────────────────────────────────────────────┐
│  Synapse v1.151.0 (Docker)                          │
│  + PostgreSQL 16 (Docker)                           │
│  server_name: matrix.yourdomain                     │
│  client API: https://matrix.yourdomain/_matrix/     │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│  Element Web v1.12.15 (Docker)                      │
│  SWAG proxy: element.yourdomain                     │
│  Operator web client for all agent rooms            │
└─────────────────────────────────────────────────────┘
```

**matrix-channel** sits on the interactive Claude Code session side:

```
Operator types in Element Web
  → Matrix room
    → matrix-channel (Node.js Channel plugin, Claude Code)
      → injects message as user input into active Claude Code session
        → agent replies, posts back to room via matrix-mcp
```

This enables permission relay — when an agent needs approval for a destructive action, it can post the prompt to Matrix, wait for a reply, and receive the operator's response within the same session.

## Stack Containers

| Container | Image | Purpose |
|-----------|-------|---------|
| `matrix-synapse` | `matrixdotorg/synapse:v1.151.0` | Homeserver |
| `matrix-db` | `postgres:16-alpine` | Synapse PostgreSQL backend |
| `matrix-element` | `vectorim/element-web:v1.12.15` | Browser client |

All three run on `claudebox-net`. Only Synapse's client API (`/_matrix/`) is exposed externally via SWAG. The admin API (`/_synapse/admin/`) is restricted to LAN CIDRs (`192.168.0.0/16`, `10.10.0.0/16`) at the proxy — external requests return 403. LAN access still requires a valid Synapse admin token (enforced natively by Synapse).

## Room Structure

11 rooms, one per agent plus shared coordination rooms:

| Room | Purpose |
|------|---------|
| `#claudebox` | Homelab ops agent |
| `#dev` | Development agent |
| `#homelab-ops` | Multi-host infrastructure agent |
| `#research` | Research agent |
| `#security` | Security audit agent |
| `#helm-build` | Helm/forge build agent |
| `#outreach` | Outreach agent |
| `#writer` | Documentation agent |
| `#memory-sync` | Memory-pipeline and doc-sync completion summaries |
| `#announcements` | Cross-agent broadcasts |
| `#general` | Operator + system channel |

Each agent's `CLAUDE.md` includes a `## Communications` section specifying its assigned room and instructing it to use `mcp__matrix__send_matrix_message` for activity updates and `mcp__matrix__post_artifact` for logs and build output.

## matrix-mcp Tools

| Tool | What It Does |
|------|-------------|
| `send_matrix_message` | Send text or markdown message to a room by short name (`dev`, `writer`, etc.) |
| `post_artifact` | Upload a file from the allowlisted paths and post a formatted link to the room |
| `get_matrix_messages` | Fetch recent messages from a room (used for reply polling) |
| `list_matrix_rooms` | Enumerate all rooms the bot account is joined to |

**post_artifact path allowlist:** `~/repos/`, `~/.claude/comms/`, `~/.claude/memory/`. Files outside these trees cannot be posted — prevents agents from inadvertently exfiltrating appdata configs, Docker secrets, or compose files.

**Markdown rendering:** Message bodies run through `bleach.clean()` with a Matrix-spec allowlist before being sent as `formatted_body`. Permitted tags include standard inline/block formatting plus Matrix-specific attributes (`data-mx-color`, `mxc://` URLs). Disallowed tags are stripped, not escaped — raw HTML cannot pass through.

## Task Dispatcher Integration

`task-dispatcher.py` routes state transition notifications to Matrix via a `matrix_notify()` helper. The routing table:

| Event | Destination |
|-------|------------|
| Task submitted | `#announcements` |
| Task approved / rejected | `#announcements` + agent's room |
| Task completed | Agent's room |
| Build handoff created | Target agent's room |
| Security audit requested | `#security` |
| Dead-letter / TTL expired | ntfy (pending-approval channel) |

ntfy retains only the dead-letter and pending-approval paths. All other dispatcher events route to Matrix.

## Nightly Cron Integration

Three PM2 cron jobs post completion summaries via `matrix-notify.py` (`~/scripts/matrix-notify.py`), a lightweight Python helper that resolves short room names to room IDs from `MATRIX_ROOM_<NAME>` env vars and sends a single message via the Synapse client API. Credentials from `~/.claude-secrets/matrix.env`; room names are validated against an explicit allowlist before sending.

| Cron job | Posts on success | Posts on failure |
|----------|-----------------|-----------------|
| `memory-pipeline` | `#memory-sync` | `#memory-sync` |
| `doc-sync` | `#memory-sync` | `#memory-sync` |
| `repo-sync-nightly` | `#announcements` | silent |

`memory-pipeline` and `doc-sync` post regardless of outcome so failures are visible in `#memory-sync` rather than disappearing into PM2 logs. `repo-sync-nightly` only posts on successful syncs — failures go to the PM2 log without a Matrix notification.

## matrix-channel

`matrix-channel` is a Node.js Claude Code Channel plugin that connects a Matrix room to an active interactive Claude Code session. It polls a specified room for new messages and injects them as user input into the running session.

**Use case:** An agent running interactively posts a question to its Matrix room. The operator replies in Element Web. `matrix-channel` picks up the reply and feeds it back to the agent without requiring a separate chat window or manual copy-paste.

**Tag injection protection:** Incoming messages are sanitized before injection — `</claude-channel>` (case-insensitive) in the message body is escaped to prevent tag-boundary injection into the channel event stream.

## Security

- **SWAG admin allowlist:** `/_synapse/admin/` restricted to LAN CIDRs (`192.168.0.0/16`, `10.10.0.0/16`) at the proxy — external requests return 403; LAN access requires a valid Synapse admin token (enforced natively)
- **homeserver.yaml permissions:** Mode 640 — readable only by the Synapse process user, not world-readable
- **post_artifact allowlist:** High-risk paths (`/opt/appdata/`, Docker compose trees) excluded; agents needing to post from those trees copy files into `~/.claude/comms/artifacts/` first
- **HTML sanitization:** All markdown content passes through `bleach.clean()` with explicit tag/attr/protocol allowlists; `html.escape()` used for user-controlled strings embedded in HTML context
- **Docker hardening:** `no-new-privileges:true`, `cap_drop: ALL` with minimal per-service `cap_add`, memory limits per container (Synapse 2 GB, PostgreSQL 1 GB, Element Web 256 MB)

## Related Docs

- [inter-agent-communication.md](inter-agent-communication.md) — agent handoff patterns and queue mechanics
- [task-dispatcher.md](task-dispatcher.md) — full routing table and dispatcher lifecycle
- [ntfy-mcp.md](ntfy-mcp.md) — ntfy (retained for dead-letter and pending-approval)
- [agent-bus.md](agent-bus.md) — NATS-backed event log for structured agent activity
