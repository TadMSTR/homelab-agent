# Multi-Host Abstraction Boundary

**Status:** Design document — no code changes  
**Created:** 2026-03-29  
**Context:** homelab-agent currently operates on a single host (claudebox). This document
defines what assumes single-host today and what would need to change to support agents
running across multiple hosts.

---

## Current Single-Host Assumption

The homelab-agent task queue, agent registry, and handoff systems all read and write
to the local filesystem under `~/.claude/` on a single host. This is intentional and
sufficient for the current single-node deployment, but the constraint is undocumented.

### Paths that assume single-host

| Path | Purpose | Change required for multi-host |
|------|---------|-------------------------------|
| `~/.claude/task-queue/` | Task YAML files; dispatcher reads/writes here | Shared backend or NFS mount |
| `~/.claude/agent-manifests/` | Agent capability registry | Shared backend or NFS mount |
| `~/.claude/agent-status/` | Per-agent heartbeat/status files | Shared backend or NFS mount |
| `~/.claude/pending-actions/<agent>.md` | Blocked-action queue per agent | Shared backend or NFS mount |
| `~/.claude/projects/<agent>/build-plans/` | Handoff queues for pending build plans | Shared backend or NFS mount |

All five categories are local filesystem reads/writes. An agent on a second host cannot
see tasks submitted to the first host, cannot register itself in the manifest directory,
and cannot receive handoffs via build-plan directories.

---

## The Four Files That Would Change

### 1. `task-dispatcher.py`

Currently reads/writes task YAML files directly from `TASK_QUEUE_DIR = Path.home() / ".claude" / "task-queue"`.

**Required abstraction:** A `TaskQueueBackend` interface with two implementations:

```python
class TaskQueueBackend(Protocol):
    def list_submitted(self) -> list[TaskFile]: ...
    def read(self, task_id: str) -> dict: ...
    def write(self, task_id: str, data: dict) -> None: ...
    def archive(self, task_id: str) -> None: ...

class LocalFSBackend(TaskQueueBackend):
    """Current implementation — reads/writes ~/.claude/task-queue/"""
    ...

class NatsKVBackend(TaskQueueBackend):
    """Future — uses NATS KV bucket TASK_QUEUE as the store"""
    ...
```

### 2. `inject-task-queue.sh`

The session-start hook that surfaces pending tasks to an agent reads task files directly
from the local filesystem. It would need to call the same backend abstraction as the
dispatcher, or be replaced by a query to a shared store.

### 3. Agent manifests

Currently a directory of YAML files at `~/.claude/agent-manifests/`. Each manifest
declares an agent's name, capabilities, scope (hosts), and approval policy.

For multi-host, manifests need to be readable by the dispatcher regardless of which host
it runs on. Options:
- **NFS mount** — mount the manifest directory from a shared host (step-0 approach)
- **NATS KV** — store manifests as KV entries under `AGENT_MANIFESTS.<agent_name>`
- **Redis hash** — `HSET agent:manifests <name> <yaml_content>`

### 4. Per-agent CLAUDE.md session-start scans

Each agent's `CLAUDE.md` has a session-start step that reads local directories for
pending build plans and security action plans:

```
ls ~/.claude/projects/research/build-plans/
ls ~/.claude/projects/security/action-plans/
```

In a multi-host setup, handoffs targeting an agent on host B would be written by an
agent on host A. These would not be visible via local filesystem reads unless the
handoff directories are on shared storage.

---

## Pragmatic First Step: NFS Shared Queue

The lowest-friction path to multi-host — without rewriting any code — is to NFS-mount
the shared state directories from a central host to all participating hosts:

```
# On each agent host, mount from the primary host (claudebox):
/mnt/claudebox/task-queue     → ~/.claude/task-queue/
/mnt/claudebox/agent-manifests → ~/.claude/agent-manifests/
/mnt/claudebox/agent-status   → ~/.claude/agent-status/
```

This covers 80% of multi-host use cases:
- Tasks submitted on any host are visible to the dispatcher on the primary host
- Agent manifests are centrally readable
- Agent status is centrally visible

**Limitation:** The dispatcher still runs on a single host. Distributed dispatch (multiple
dispatcher instances competing for tasks) would require locking, which NFS doesn't provide
reliably. Single-dispatcher-multi-worker is the safe model with this approach.

**New NFS exports required:** Each new directory would need an atlas-side NFS export (or
claudebox acting as NFS server). This is an infrastructure change requiring manual setup.

---

## Full Abstraction Path

For true distributed operation without NFS:

1. **NATS KV as task queue** — replace `LocalFSBackend` with `NatsKVBackend`. NATS KV
   supports concurrent access, atomic updates, and cross-host visibility natively. The
   `TASKS` JetStream stream already exists; add a KV bucket `TASK_QUEUE`.

2. **NATS KV as agent registry** — replace manifest YAML files with KV entries under
   `AGENT_MANIFESTS`. Each agent registers itself on startup; the dispatcher queries
   the KV bucket instead of reading local files.

3. **Distributed dispatcher** — with NATS KV as the backend, multiple dispatcher instances
   can run on different hosts. Use NATS KV atomic CAS (compare-and-swap) to claim tasks
   without a central lock.

4. **Handoff delivery** — replace filesystem-based build-plan directories with NATS
   subjects (`handoffs.<agent_name>`) or a KV bucket. Agents subscribe to their subject
   at session start instead of scanning local directories.

---

## Decision Criteria for Upgrade

The NFS approach is appropriate when:
- You have 2–3 agent hosts
- The dispatcher can remain on a single primary host
- You want zero code changes

The NATS KV approach is appropriate when:
- You have 3+ agent hosts or need the dispatcher to be resilient
- You want agents to be truly independent of the primary host
- You're willing to refactor `task-dispatcher.py` and the inject hook

---

## Current Status

Single-host operation on claudebox is the only supported configuration. The NATS
infrastructure (JetStream, `TASKS` stream) is already deployed and would serve as the
natural backend for a future distributed implementation.

No timeline for multi-host operation is planned. This document exists to preserve the
design context so the abstraction work can be picked up without rediscovery.
