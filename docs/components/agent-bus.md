# agent-bus

agent-bus is a FastMCP server that provides a unified inter-agent event log for forge's
multi-agent setup. Agents log communication events (task handoffs, audit requests, build
completions, artifact creation) via MCP tool calls. Events are written to local JSONL
files and federated to NATS JetStream for real-time observability.

- **Source:** `~/repos/personal/agent-bus/`
- **PM2 name:** `agent-bus` (id 9)
- **Transport:** stdio (launched by Claude Code via scoped-mcp)
- **NATS subject:** `agent-bus.<hostname>.events`

## Tools

| Tool | What it does |
|------|-------------|
| `log_event` | Record an inter-agent event with type, source, target, and summary |
| `query_events` | Query the event log by date range, type, source, or target |
| `get_event` | Retrieve a single event by ID |
| `verify_chain` | Walk a JSONL log file and verify its hash chain and signatures |
| `get_status` | Return current server configuration, signing mode, and registered key count |

## Event Vocabulary

Events are split into **cross-agent** (written to `cross-agent` scope) and session-local
scopes. High-priority events trigger ntfy notifications.

| Type | Scope | Priority | When to use |
|------|-------|----------|-------------|
| `task.dispatched` | cross | — | A task was submitted to the task queue |
| `task.approved` | cross | — | A queued task was approved for execution |
| `task.completed` | cross | — | A task finished successfully |
| `task.failed` | cross | **high** | A task failed |
| `task.routing-failed` | cross | **high** | A task could not be routed to an agent |
| `handoff.created` | cross | **high** | A doc or artifact handoff was written |
| `handoff.picked-up` | cross | — | A handoff was acknowledged by the target agent |
| `handoff.completed` | cross | — | A handoff was fully processed |
| `audit.requested` | cross | **high** | A security audit was dispatched |
| `audit.completed` | cross | — | A security audit finished |
| `build-plan.created` | cross | — | A build plan was written to artifacts |
| `build.started` | cross | — | A build began execution |
| `build.completed` | cross | — | A build finished |
| `deploy.started` | cross | — | A deployment began |
| `deploy.completed` | cross | — | A deployment finished |
| `diagnose.started` | cross | — | A diagnostic investigation began |
| `diagnose.completed` | cross | — | A diagnostic investigation finished |
| `preflight.started` | cross | — | A build preflight check began |
| `preflight.completed` | cross | — | A build preflight check finished |
| `security.finding` | cross | — | A security finding was recorded |
| `artifact.untracked` | cross | — | reconcile.py found an artifact with no prior log entry |

## Architecture

```
Agent  ──log_event()──→  server.py
                              │
                              ├─→ ~/.claude/comms/logs/YYYY-MM-DD-{scope}.jsonl
                              ├─→ NATS (inline publish, real-time)
                              └─→ ntfy (high-priority events: audit, task.failed)

Background federation loop (every 30s):
  File log + offset cursor → NATS (gap-fill for NATS downtime)

reconcile.py (PM2 cron, 5 min):
  Scan ~/.claude/comms/artifacts/ → log artifact.untracked for new files

cleanup.sh (PM2 cron, 3:50 AM):
  Purge cross-agent logs > 90 days, session logs > 30 days
```

## Log Location

Events are written to `~/.claude/comms/logs/YYYY-MM-DD-<scope>.jsonl`. The scope is
derived from event metadata (e.g., `cross-agent`, or a specific agent name).

## NATS Integration

agent-bus publishes to `agent-bus.<hostname>.events` on the local NATS server
(`nats://localhost:4222`). Downstream consumers (dashboards, monitoring workflows) can
subscribe to this subject for real-time event streams. NATS downtime is handled by the
background federation loop re-publishing from the file log.

## Signature Verification

agent-bus supports ed25519 signature verification on incoming `log_event` calls.
Signatures are produced by scoped-mcp's signing hook (`scoped_mcp.contrib.signing_hook`)
at the time of the tool call; the public key is looked up from `~/.claude/comms/agent-keys.json`.

Verification mode is controlled by `AGENT_BUS_VERIFY_SIGNATURES` in the agent-bus `.env`:

| Mode | Behavior |
|------|----------|
| `off` | No verification — all events accepted |
| `warn` | Invalid signatures logged; events accepted regardless |
| `enforce` | Invalid signatures rejected with error; **unsigned events accepted** |

Current mode: **enforce** (set 2026-05-28).

Unsigned events are always accepted in enforce mode — the server distinguishes between
"no signature present" (allowed) and "signature present but invalid" (rejected). This lets
agents that haven't restarted since signing was enabled continue logging without errors.

Public keys are stored in `~/.claude/comms/agent-keys.json` (chmod 644). Use `get_status`
to confirm which agents have registered keys.

## Related Docs

- [nats.md](nats.md) — NATS JetStream event bus
- [task-queue-mcp.md](task-queue-mcp.md) — task state alongside agent-bus events
- [scoped-mcp-forge.md](scoped-mcp-forge.md) — signing hook wiring and Vault key storage
