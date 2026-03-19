# NATS JetStream

NATS is a lightweight message broker with a JetStream persistence layer. In this stack it serves as the event bus for agent orchestration — task state transitions flow through it as subjects that anything on the host can subscribe to. It's additive to the file-based task queue, not a replacement: the queue files remain the source of truth, and all NATS publishes are fire-and-forget.

The immediate use is observability. When the dispatcher approves a task, sends it to approval, or marks it failed, a message lands on a JetStream subject. Future subscribers — dashboards, automation, agents — can consume those events without polling the filesystem. The infrastructure is there; today's consumers are limited to whatever's watching.

## Why NATS

The file-based task queue works well for task lifecycle, but file polling is a poor fit for anything that wants near-real-time event feeds. NATS solves this cleanly: the dispatcher publishes transitions as they happen, consumers subscribe at any granularity (`tasks.>` for everything, `tasks.approved` for just approvals), and JetStream retains messages so a consumer starting later can replay what it missed.

The alternative — having consumers poll the YAML files — means each new consumer adds another reader that has to understand the task schema and walk the directory. NATS decouples event production from consumption: the dispatcher doesn't know or care who's listening.

NATS was chosen over Redis pub/sub (already have Valkey, but it's scoped to Authelia), Mosquitto/MQTT (well-matched to IoT, not to agent events), and a full message queue like RabbitMQ (too heavy for a homelab event bus). NATS 2.10 is a single static binary, the Docker image is under 20MB, and JetStream is built in.

## How It Works

NATS runs as a single Docker container on `claudebox-net`. JetStream is enabled with a file-backed store.

**Ports (localhost-only):**
- `4222` — client connections (publisher/subscriber access)
- `8222` — HTTP monitoring dashboard (read-only, proxied at `nats.yourdomain` behind Authelia)

**JetStream store:** `/opt/appdata/nats/data` — 256MB memory cap, 2GB file cap.

### Streams

Two streams are configured:

**TASKS** — captures all task lifecycle events. Subjects: `tasks.>`. Retention: 30 days.

| Subject | Published by | When |
|---------|-------------|------|
| `tasks.submitted` | task-dispatcher.py | New task picked up from the queue |
| `tasks.approval-requested` | task-dispatcher.py | Task gated at approval — ntfy notification sent |
| `tasks.approved` | task-dispatcher.py | Task auto-approved and handed to agent |
| `tasks.failed` | task-dispatcher.py | Task routing failed (no manifest match, parse error) |
| `tasks.working` | inject-task-queue.sh | Task surfaced to agent at session start |

**AGENT_EVENTS** — reserved for future agent activity events. Subjects: `agents.>`. Retention: 7 days, 500 messages per-subject cap. Currently empty — no publishers yet.

### Message Format

All messages are JSON. Example for `tasks.approved`:

```json
{
  "task_id": "a7f3d2c1-...",
  "target_agent": "claudebox",
  "summary": "Deploy qmd stack update per plan"
}
```

Fields vary by subject — `tasks.submitted` includes `risk_level`, `tasks.failed` includes `summary` only. Payloads are intentionally minimal; full task context lives in the queue file, addressed by `task_id`.

## Configuration

**Docker Compose:** `~/docker/nats/docker-compose.yml`

**Server config:** `~/docker/nats/nats-server.conf`

```
port: 4222
http_port: 8222

jetstream {
  store_dir: /data
  max_memory_store: 256MB
  max_file_store: 2GB
}
```

No auth configured — access is restricted to localhost via the port binding. If you expose NATS beyond localhost, configure authentication (NKeys or token-based) in the server config.

**SWAG proxy:** The monitoring dashboard at port 8222 is proxied behind Authelia for browser-based inspection of stream state, message counts, and consumer activity. The client port (4222) is not proxied — only accessible from the host.

## NATS CLI

The NATS CLI (`nats`) is installed at `~/.local/bin/nats` (v0.3.1). Useful for checking stream state and replaying events without writing subscriber code.

```bash
# Check stream state
nats stream ls
nats stream info TASKS
nats stream info AGENT_EVENTS

# Watch live events
nats sub "tasks.>"

# Replay recent TASKS messages
nats stream get TASKS --last 10

# Subscribe with JetStream durable consumer (persists position across restarts)
nats consumer add TASKS my-consumer
nats consumer next TASKS my-consumer
```

## Integration Points

**task-dispatcher.py:** Publishes to `tasks.submitted`, `tasks.approval-requested`, `tasks.approved`, and `tasks.failed` on each dispatcher run (every 2 minutes). Uses a subprocess call to the `nats` CLI binary — no Python NATS library required. Failures are caught and logged without interrupting the dispatcher.

**inject-task-queue.sh:** Publishes to `tasks.working` for each task surfaced at agent session start. Same fire-and-forget pattern — if NATS is down, the task injection still completes.

**File queue:** NATS events are derived from queue file transitions, not authoritative. If NATS is unavailable, the task queue operates normally — nothing depends on NATS for task routing or delivery. Restart NATS and events resume on the next dispatcher run.

**Future consumers:** The AGENT_EVENTS stream is wired for agent lifecycle events (session start, tool calls, memory writes) that agents could publish. No publishers exist yet — the stream is reserved infrastructure for when a consumer exists to justify it.

## Gotchas and Lessons Learned

**Fire-and-forget means no delivery guarantee.** A NATS publish during a dispatcher run that fails (container down, port unreachable) is silently dropped — the dispatcher doesn't retry and JetStream doesn't buffer the failed publish. For observability this is acceptable; for anything that needs guaranteed delivery, use the file queue.

**The `nats` CLI must be in `$PATH` for the dispatcher.** `task-dispatcher.py` calls `nats` by name, not by full path. Make sure `~/.local/bin` is in `PATH` for the PM2 environment, or use the full path in the subprocess call. Check with `pm2 env task-dispatcher | grep PATH`.

**Duplicate Window is 2 minutes.** The TASKS stream has a 2-minute duplicate detection window keyed on message ID. The dispatcher doesn't set explicit message IDs, so deduplication doesn't apply — but be aware if you add producers that publish rapidly with explicit IDs.

**8222 is monitoring-only.** The HTTP port exposes the NATS monitoring dashboard (subject counts, stream stats, health check at `/healthz`). It does not allow publishing or consuming — that's client port 4222. Don't confuse the two when writing proxy rules.

**JetStream is single-node.** This is a single-instance deployment with no clustering or replication. Data survives container restarts (file-backed store), but not host failures without a backup. The `/opt/appdata/nats/data` directory is covered by the Docker appdata backup script.

## Standalone Value

NATS is not required for the task queue to function — the dispatcher and agents work entirely through filesystem operations. It adds observability and a pub/sub surface for future automation. If you're building the agent orchestration system without a need for event streaming yet, skip this and add it later when you have a concrete consumer in mind. The task queue is designed to be NATS-agnostic.

## Further Reading

- [NATS documentation](https://docs.nats.io/)
- [JetStream documentation](https://docs.nats.io/nats-concepts/jetstream)
- [NATS CLI reference](https://github.com/nats-io/natscli)

---

## Related Docs

- [Agent Orchestration](agent-orchestration.md) — the task queue and dispatcher that publish to NATS
- [Architecture overview](../../README.md#layer-3--multi-agent-claude-code-engine) — Layer 3 context
