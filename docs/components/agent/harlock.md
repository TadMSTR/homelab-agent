# Harlock (personal-agent)

A resident Matrix bot agent that maintains a persistent Claude Code session and responds in a dedicated Matrix room. Unlike task-queue agents that start and stop per-task, Harlock is always-on and handles open-ended personal assistant work.

## Overview

Harlock wraps the `personal-agent` manager in a long-running PM2 process. The manager polls a Matrix room, forwards messages into a Claude Code subprocess, and handles session lifecycle — rollover, summarization, and memory harvest.

## Process

| Field | Value |
|-------|-------|
| PM2 name | `personal-agent-harlock` |
| Script | `~/repos/personal/personal-agent/start.sh` |
| Interpreter | bash |
| Mode | always-on (no cron schedule) |
| Isolated user | `agent-harlock` |

## Architecture

```
Matrix room (#harlock:<homeserver>)
        │
        ▼
manager.py  (personal-agent, runs as operator user)
        │  polls via Matrix client
        │  launches subprocess
        ▼
claude CLI  (runs as agent-harlock)
        │
        ├─ Project:       /home/agent-harlock/.claude/projects/harlock/
        ├─ Working notes: ~/.claude/memory/agents/harlock/working/
        └─ Session notes: ~/.claude/memory/agents/harlock/session/
```

## Configuration (config.harlock.yml)

```yaml
trusted_sender: "@operator:example.com"
mention_user: "@operator:example.com"

poll_interval_seconds: 5
max_message_length: 4000
subprocess_timeout_seconds: 600

# Roll the session at this input-token fill.
# 130k sits below Sonnet's ~167k auto-compact trigger
# (200k window, CLAUDE_CODE_AUTO_COMPACT_WINDOW=180000).
rollover_budget: 130000

deployment:
  name: "harlock"
  room_id: "!<room-id>:<homeserver>"
  model: "claude-sonnet-4-6"
  agent_user: "agent-harlock"
  project_dir: "/home/agent-harlock/.claude/projects/harlock"
  agent_home: "/home/agent-harlock"
  working_note_dir: "/home/operator/.claude/memory/agents/harlock/working"
  session_note_dir: "/home/operator/.claude/memory/agents/harlock/session"
  ollama_url: "http://localhost:11434"
  ollama_model: "summarize:latest"
  ollama_timeout: 60
  memsearch_bin: "/home/operator/.local/bin/memsearch"

session_retention_days: 30
```

`rollover_budget` must be re-derived if the model changes — it depends on the context window size and the auto-compact threshold.

## SOUL.md (identity anchor)

On every new session open, the manager reads `project_dir/SOUL.md` and prepends it to the first prompt, before any warm handoff or memsearch injection. This gives Harlock a persistent identity context that survives session rollovers without depending on the agent's own memory of prior sessions.

Location: `<project_dir>/SOUL.md` (e.g. `/home/agent-harlock/.claude/projects/harlock/SOUL.md`)

Behavior when absent: silently skipped — no startup failure.

The rollover handoff preamble also includes a two-line pointer to SOUL.md so Harlock can locate its identity context after a rollover (via `githost-mcp` if needed).

## Memory systems

Harlock has access to four memory systems to compensate for context rollover and idle harvest:

| System | Tool | What it contains |
|--------|------|-----------------|
| memsearch | `memsearch-mcp` | Hybrid vector+BM25+reranker search over session, working, and docs tiers |
| memory-metadata | `memory-metadata-mcp` | List/filter notes by tag, date, or agent |
| graphiti | `graphiti` | Knowledge graph — facts, decisions, service relationships |
| qmd | `qmd` | Semantic search over indexed documentation collections |

**Cold-start injection:** the manager (running as the operator user) runs memsearch before opening a new session that has no warm handoff, and injects the top results into the first prompt. This seeds Harlock with relevant prior context even on a fresh chain with no rollover summary.

**Session and working notes:**

| Path | Tier | Written by |
|------|------|-----------|
| `~/.claude/memory/agents/harlock/session/` | session | Harlock; indexed by idle harvest |
| `~/.claude/memory/agents/harlock/working/` | working | Harlock directly |

Session notes are indexed into memsearch by the idle harvest process and become searchable across future sessions.

## Session rollover

When input tokens reach `rollover_budget`, the manager:

1. Sends the tail of the conversation to Ollama for summarization
2. Falls back to raw tail if Ollama times out (60s)
3. Starts a fresh Claude Code session with the summary injected as context

## Idle harvest

When the session is idle, the manager calls memsearch to index the session notes into the memsearch session tier. This makes recent conversation context retrievable in future sessions.

## Isolation

- Claude subprocess runs as `agent-harlock` (dedicated system user, no login shell)
- AppArmor profile enforced on the subprocess
- Bot credentials in `~/.claude-secrets/personal-agent.env` — sourced by `start.sh`, not stored in the config file

## Operations

Restart:
```bash
pm2 restart personal-agent-harlock
```

View logs:
```bash
pm2 logs personal-agent-harlock
```

Status:
```bash
pm2 show personal-agent-harlock
```

Stop gracefully:
```bash
pm2 stop personal-agent-harlock
```

## scoped-mcp integration

Harlock has a dedicated scoped-mcp manifest separate from task-queue agents. The manifest reflects personal assistant use — broader read access, no destructive system operations.
