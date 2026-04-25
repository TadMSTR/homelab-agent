# Matrix Dispatcher

A PM2 daemon that watches each agent's Matrix room for messages from a trusted sender, spawns `claude -p` sessions, and posts responses back. The operator sends a message to an agent's room in Element Web; the agent replies. No manual session management required.

## Why It Exists

Before the dispatcher, invoking an agent required either opening a terminal and starting a Claude Code session manually or waiting for the autonomous pipeline to trigger a RemoteTrigger session. Neither worked well for quick, conversational interactions.

The dispatcher adds a third invocation path: send a message to `#research` (or any agent room) and the agent replies directly in the room. Matrix threads provide the structure — room-root messages spawn new sessions; thread replies resume them (v2+). The operator interface is Element Web, which works from any browser on the network.

## Architecture

```
@ted sends message to #research
        ↓
matrix-dispatcher (PM2, polls every 5s)
        ↓  room-root message → spawn new session
        ↓  thread reply (v2+) → resume prior session
claude -p --session-id <uuid> "<injected-prefix><user-message>"
  cwd: /home/user/.claude/projects/<agent-name>
        ↓  stdout
Dispatcher posts response to Matrix room
  (with @ted:yourdomain mention for push notification)
```

**Routing discriminator:** Matrix thread structure only — room-root spawns, thread reply resumes. No timers, no AI judgment about intent.

**Acknowledgment:** Before spawning, the dispatcher posts a brief message to the room (`Working... (session <short-uuid>)`). The final response is posted as a thread reply to that message, creating a clean request→response pair.

**Response chunking:** If stdout exceeds `max_message_length` (default 4000 chars), the dispatcher splits on paragraph boundaries and sends sequential messages in the same thread. Matrix silently truncates past the API limit without this.

**@mention:** All responses include `@ted:yourdomain` at the start. Element treats this as a mention and triggers a push notification to Element mobile.

## Config

`~/repos/personal/matrix-dispatcher/config.yml`:

```yaml
trusted_sender: "@ted:yourdomain"
mention_user: "@ted:yourdomain"
poll_interval_seconds: 5
max_message_length: 4000
session_retention_days: 30    # v3+ nightly cleanup

agents:
  research:
    room_id: "!roomid:yourdomain"
    project_dir: "/home/user/.claude/projects/research"
  claudebox:
    room_id: "!roomid:yourdomain"
    project_dir: "/home/user/.claude/projects/claudebox"
  dev:
    room_id: "!roomid:yourdomain"
    project_dir: "/home/user/.claude/projects/dev"
  homelab-ops:
    room_id: "!roomid:yourdomain"
    project_dir: "/home/user/.claude/projects/homelab-ops"
  security:
    room_id: "!roomid:yourdomain"
    project_dir: "/home/user/.claude/projects/security"
  writer:
    room_id: "!roomid:yourdomain"
    project_dir: "/home/user/.claude/projects/writer"
```

`project_dir` is the working directory for `claude -p` — the project's `CLAUDE.md` must be present there.

## Credentials

The dispatcher polls and posts using a dedicated Matrix bot account. Credentials are stored at `~/.claude-secrets/matrix-dispatcher.env` (chmod 600) and sourced at PM2 startup via `start.sh`:

```bash
DISPATCHER_HOMESERVER=https://matrix.yourdomain
DISPATCHER_USER_ID=@dispatcher-bot:yourdomain
DISPATCHER_ACCESS_TOKEN=<access-token>
```

The dispatcher account needs to be a member of every agent room it watches. Per-agent Synapse accounts (`@agent.research:yourdomain`, `@agent.writer:yourdomain`, etc.) are separate — those are for scoped-mcp mid-session posting by agents, not for the dispatcher's poll/post loop.

## Per-Agent Synapse Accounts

Six accounts following the `@agent.<name>:yourdomain` convention were created on the claudebox Synapse homeserver during deployment:

| Account | Primary room | Also joined to |
|---------|-------------|----------------|
| `@agent.research:yourdomain` | `#research` | `#approvals`, `#announcements` |
| `@agent.claudebox:yourdomain` | `#claudebox` | `#approvals`, `#announcements` |
| `@agent.dev:yourdomain` | `#dev` | `#approvals`, `#announcements` |
| `@agent.homelab-ops:yourdomain` | `#homelab-ops` | `#approvals`, `#announcements` |
| `@agent.security:yourdomain` | `#security` | `#approvals`, `#announcements` |
| `@agent.writer:yourdomain` | `#writer` | `#approvals`, `#announcements` |

These accounts enable agents to post mid-session via the scoped-matrix MCP server (separate from matrix-mcp) without routing through the dispatcher's poll/post path. Credentials stored at `~/.claude-secrets/matrix-<agent>.env` (chmod 600).

## Scoped-MCP Manifests

Each agent has a `~/.claude/manifests/<agent>.yml` scoped-mcp manifest that restricts the agent's Matrix posting to its own room plus shared rooms:

```yaml
matrix:
  homeserver: https://matrix.yourdomain
  user_id: "@agent.research:yourdomain"
  access_token: "<agent-token>"
  allowed_rooms:
    - "#research:yourdomain"
    - "#approvals:yourdomain"
    - "#announcements:yourdomain"
```

The scoped-mcp server starts per-agent when the dispatcher spawns a session — the manifest is passed via `--manifest` flag or loaded from the standard path for that agent's project directory.

## PM2

```
Service name: matrix-dispatcher
PM2 ID:       31
Start:        pm2 start ecosystem.config.js
Logs:         ~/.pm2/logs/matrix-dispatcher-out.log
              ~/.pm2/logs/matrix-dispatcher-error.log
```

`ecosystem.config.js` sources `~/.claude-secrets/matrix-dispatcher.env` at startup via a `start.sh` wrapper. The venv is at `~/repos/personal/matrix-dispatcher/venv/`.

## Phase Status

| Phase | Status | Description |
|-------|--------|-------------|
| v1 | ✓ deployed | Spawn-only loop, acknowledgment message, @mention, response chunking |
| v2 | planned | SQLite + thread-based resume (`~/.claude/data/matrix-dispatcher/sessions.db`); restart-safe |
| v3 | planned | `/sessions`, `/recap`, `/mirror`, `/help` commands; nightly cleanup (30-day retention) |
| Phase 4 | planned | Concurrency lock, subprocess timeout, rate limiting, `/cancel`, error surfacing, startup notification |

**v2 routing logic:** Room-root messages always spawn. Thread replies check SQLite for a matching `thread_root_id` — match resumes, no match spawns as new. Orphaned replies (from sessions started before the dispatcher) are treated as new spawns. `poll_state` table replaces the v1 JSON poll-token file; migration runs automatically on first v2 start.

**v3 commands** (intercept before spawning):
- `/sessions` — numbered list of recent sessions; reply to a list item to resume that session
- `/recap [N]` — last N turns of the most recent session (default 5); read-only, no resume registered
- `/mirror` — registers the most recent CloudCLI-started session in SQLite so thread replies can resume it
- `/help` — command reference

## File Layout

```
~/repos/personal/matrix-dispatcher/
├── dispatcher.py       # main daemon
├── config.yml          # live config (not committed — contains room IDs)
├── config.example.yml  # committed template
├── requirements.txt    # pinned deps (matrix-nio, pyyaml)
├── ecosystem.config.js # PM2 definition
├── start.sh            # sources credentials env, execs dispatcher
└── venv/               # local venv
~/.claude/data/matrix-dispatcher/
├── poll-tokens.json           # per-agent sync tokens (v1)
└── sessions.db                # SQLite session store (v2+)
~/.claude-secrets/
├── matrix-dispatcher.env      # dispatcher bot credentials (chmod 600)
├── matrix-agent.research.env  # per-agent credentials (chmod 600)
└── ...
~/.claude/manifests/
├── research.yml               # scoped-mcp manifest for @agent.research
└── ...
```

## Security

- **Sender gate:** Every inbound event is checked against `trusted_sender` before any processing — silently discarded if it doesn't match. Applies to spawns, resumes, and all dispatcher commands.
- **Minimal subprocess env:** Each `claude -p` spawn receives a filtered environment: `HOME`, `PATH`, `AGENT_ID`, `AGENT_TYPE`, and required `CLAUDE_*` vars only. Dispatcher credentials and other secrets in the daemon env do not flow into agent processes.
- **Log policy:** PM2 log files contain timestamps, event IDs, session IDs, room IDs, actions, and exit codes only. Message body content (user messages and agent stdout) is never written to logs.
- **SQLite parameterized queries (v2+):** All values sourced from Matrix event metadata (thread root IDs, room IDs, agent names) use parameterized statements throughout — no f-string or `.format()` SQL construction.
- **Pinned deps:** `requirements.txt` pins `matrix-nio` and `pyyaml` to exact versions.
- **3 Low security findings resolved** post-deployment: L1 (sync replay via atomic poll-token write), L2 (CLAUDE_* glob removed from subprocess env allowlist), L3 (poll-token file write made atomic).

## Related Docs

- [matrix.md](matrix.md) — Synapse homeserver, matrix-mcp, matrix-admin-bot, matrix-channel
- [inter-agent-communication.md](inter-agent-communication.md) — agent handoff patterns and queue mechanics
- [agent-orchestration.md](agent-orchestration.md) — autonomous pipeline and RemoteTrigger invocation
