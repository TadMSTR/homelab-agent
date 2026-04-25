# Matrix Dispatcher

A PM2 daemon that watches each agent's Matrix room for messages from a trusted sender, spawns `claude -p` sessions, and posts responses back. The operator sends a message to an agent's room in Element Web; the agent replies. No manual session management required.

## Why It Exists

Before the dispatcher, invoking an agent required either opening a terminal and starting a Claude Code session manually or waiting for the autonomous pipeline to trigger a RemoteTrigger session. Neither worked well for quick, conversational interactions.

The dispatcher adds a third invocation path: send a message to `#research` (or any agent room) and the agent replies directly in the room. Matrix threads provide the structure — room-root messages spawn new sessions; thread replies resume them. The operator interface is Element Web, which works from any browser on the network.

## Architecture

```
@ted sends message to #research
        ↓
matrix-dispatcher (PM2, polls every 5s)
        ↓  room-root message    → spawn new session
        ↓  thread reply         → resume prior session via --resume <session_id>
        ↓  !<command>           → intercepted (no spawn)
asyncio.create_subprocess_exec("claude", "-p", "--session-id", uuid, prompt, ...)
  cwd: /home/user/.claude/projects/<agent-name>
        ↓  stdout
Dispatcher posts response to Matrix room
  (with @ted:yourdomain mention for push notification)
```

**Routing discriminator:** Matrix thread structure only — room-root spawns, thread reply resumes. No timers, no AI judgment about intent. The `extract_thread_root()` helper returns the thread root event ID or `None`, replacing the v1 boolean `is_room_root()` check.

**Element reply quirk:** Element sometimes sends thread replies with `m.in_reply_to` rather than the spec-correct `rel_type=m.thread`. The `event_aliases` table maps acknowledgment and response chunk event IDs back to their parent session, so a reply to any of those events still routes to the correct session for resume.

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
session_retention_days: 30
startup_notification_agent: claudebox    # room to post on dispatcher launch

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
| v0.1 | ✓ deployed | Spawn-only loop, acknowledgment message, @mention, response chunking |
| v0.2 | ✓ deployed | SQLite session store, thread-based resume, `event_aliases` for Element reply quirk |
| v0.3 | ✓ deployed | `!sessions`, `!recap`, `!mirror`, `!help` commands; 30-day retention cleanup |
| v0.4 | ✓ deployed | Async subprocess, per-room concurrency lock, per-room rate limit, `!cancel`, startup notification |

### v0.2 — SQLite resume

Sessions are persisted to `~/.claude/data/matrix-dispatcher/sessions.db` (WAL mode, parameterized queries throughout). Three tables:

| Table | Purpose |
|-------|---------|
| `sessions` | One row per spawned session; columns include `thread_root_id`, `room_id`, `agent`, `session_id`, `created_at`, `last_used_at` |
| `event_aliases` | Maps ack and response chunk event IDs to their parent session — needed because Element sometimes uses `m.in_reply_to` instead of `rel_type=m.thread` |
| `poll_state` | Per-room Matrix sync tokens (replaces v1 `poll-tokens.json`; one-time migration runs automatically on first v0.2 start) |

**Routing logic:** Room-root messages always spawn fresh sessions with a new UUID4 session ID. Thread replies look up the thread root in `sessions`, then fall back to `event_aliases` if not found. A match resumes via `claude -p --resume <session_id>`; no match falls back to spawning. Sessions survive PM2 restarts.

The spawn prompt explicitly instructs agents not to call Matrix MCP tools — the dispatcher owns all Matrix posting, so an agent posting via MCP would create double-posts.

### v0.3 — Commands and retention

Bang-prefix commands are intercepted before any spawn or resume. The `!` prefix is intentional: Element intercepts `/`-prefixed messages client-side (IRC-style commands like `/me`, `/join`, `/help`) and never sends them to Matrix, so the dispatcher would never see them.

| Command | What it does |
|---------|-------------|
| `!help` | List of dispatcher commands |
| `!sessions` | 10 most recent sessions in the room as numbered items; reply-in-thread to resume |
| `!recap [N]` | Read the most recent session's JSONL transcript and post the last N user+assistant turns (default 5, cap 20). Read-only — no spawn, no resume registered |
| `!mirror` | Register the most recent untracked JSONL session in `project_dir` under a new thread root, so a CloudCLI-started session can be resumed via Matrix replies |
| `!cancel` | Send SIGTERM to the active subprocess in this room and confirm |

**Retention cleanup:** `cleanup_loop()` runs at startup and every 24 hours, deleting sessions older than `session_retention_days` (default 30) and any orphaned `event_aliases` rows. Manual run: `python dispatcher.py --cleanup`.

### v0.4 — Hardening

- **Async subprocess:** `subprocess.run` was replaced with `asyncio.create_subprocess_exec` + `asyncio.wait_for`. The previous sync call blocked the entire poll loop for the duration of a session, so `!cancel` and other commands could not be processed concurrently. This was Phase 2 audit finding L2; the v0.4 rewrite resolves it.
- **Per-room concurrency lock:** `_room_locks[room_id]` serializes spawn/resume per agent, so two messages arriving in the same room in the same poll tick don't interleave.
- **Per-room spawn rate limit:** 10s minimum gap between spawns in the same room. Resumes are unaffected. Guards against runaway loops if a misconfigured agent ever spams its own room.
- **Active process tracking:** `_active_processes[room_id]` holds the live subprocess for the duration of the run, enabling `!cancel` to send SIGTERM. The pipe is drained via `communicate()` after kill to prevent FD leaks.
- **Startup notification:** Posts a one-line launch message to the room configured by `startup_notification_agent` (default `claudebox`) so the operator can see when the dispatcher restarts.
- **Resume UUID validation:** JSONL stems are parsed with `uuid.UUID()` before being passed to `--resume` argv, preventing untrusted strings from reaching the subprocess.

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
└── sessions.db                # SQLite (sessions, event_aliases, poll_state)
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
- **SQLite parameterized queries:** All values sourced from Matrix event metadata (thread root IDs, room IDs, agent names) use parameterized statements throughout — no f-string or `.format()` SQL construction.
- **`sessions.db` permissions:** Created with mode 600 — readable only by the dispatcher process user. Contains session IDs and event metadata that should not be world-readable.
- **Resume argv validation:** JSONL stems are parsed with `uuid.UUID()` before being passed to `--resume`, so unparseable strings cannot reach the subprocess.
- **Pinned deps:** `requirements.txt` pins `matrix-nio` and `pyyaml` to exact versions.

**Security findings resolved across phases:**

| Phase | Finding | Fix |
|-------|---------|-----|
| v0.1 L1 | Sync replay on daemon restart | Atomic poll-token write (`.tmp` + rename) |
| v0.1 L2 | `CLAUDE_*` glob in subprocess env | Replaced with explicit allowlist of required vars |
| v0.1 L3 | Non-atomic poll-token write | Same fix as L1 (atomic write) |
| v0.2 L1 | `sessions.db` world-readable | `chmod 600` at creation |
| v0.2 L3 | `extract_thread_root` type confusion | Type guard added on return value |
| v0.2 L2 | Sync subprocess in async loop | Resolved in v0.4 via async subprocess rewrite |
| v0.4 L1 | Sequential poll loop blocked `!cancel` | Concurrent `asyncio.create_task` handlers; cancel registration wait, rate-limit and resume `_post_response` inside the room lock; clean shutdown drain |
| v0.4 L2 | Subprocess pipe leak after SIGTERM | `communicate()` drain after kill |
| v0.4 L3 | Untrusted UUID passed to `--resume` argv | `uuid.UUID()` parse check on JSONL stems |

## Related Docs

- [matrix.md](matrix.md) — Synapse homeserver, matrix-mcp, matrix-admin-bot, matrix-channel
- [inter-agent-communication.md](inter-agent-communication.md) — agent handoff patterns and queue mechanics
- [agent-orchestration.md](agent-orchestration.md) — autonomous pipeline and RemoteTrigger invocation
