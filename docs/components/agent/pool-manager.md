# Pool Manager (agent-pool-manager)

Pre-warms ephemeral agent session directories so that headless agent launches can claim
a ready-made working directory instead of creating one from scratch.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `agent-pool-manager` |
| Type | cron |
| Schedule | `* * * * *` (every minute) |
| Script | `~/scripts/agent-pool-manager.sh` |
| Port | — (no listener) |

## Current Status

The pool manager is a **placeholder** — it runs on schedule but the implementation is
minimal. pm2-services.md notes "no impl yet". The script creates symlinked agent session
directories in `/tmp/agent-sessions/` with CLAUDE.md and skills directories linked from
golden images under `/opt/agents/`.

## How It Works

1. Reads desired pool sizes (currently only `research=2`, others on-demand)
2. Counts existing warm sessions in `/tmp/agent-sessions/`
3. Creates symlinked clones for any deficit
4. Logs activity to `~/logs/agent-pool-manager.log`

## Pool Targets

| Agent | Warm clones | Notes |
|-------|-------------|-------|
| research | 2 | Frequently invoked by cron |
| others | 0 | Created on demand by task-dispatcher |

## Dependencies

- Golden image directories under `/opt/agents/` — source for symlinks
- [task-dispatcher](task-dispatcher.md) — consumes pre-warmed sessions when launching agents

## Operations

```bash
pm2 logs agent-pool-manager --lines 20   # last run output
ls /tmp/agent-sessions/                   # current pool state
```

## Related Docs

- [task-dispatcher.md](task-dispatcher.md) — dispatches tasks to agent sessions
- system-agents — agent types that use the pool
