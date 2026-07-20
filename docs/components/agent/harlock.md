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
        │  ▲
        │  │ manager posts subprocess output back to the room
        ▼  │ as the bot user (auto-relay)
manager.py  (personal-agent, runs as operator user)
        │  polls via Matrix client, owns the only Matrix connection
        │  launches subprocess
        ▼
claude CLI  (runs as agent-harlock)  — no Matrix send tool
        │  emits stream-json; final text is captured, not sent
        ├─ Project:       /home/agent-harlock/.claude/projects/harlock/
        ├─ Working notes: ~/.claude/memory/agents/harlock/working/
        └─ Session notes: ~/.claude/memory/agents/harlock/session/
```

## Matrix integration (auto-relay)

Harlock's Claude subprocess has **no Matrix send tool** — its scoped-mcp manifest
carries no `matrix-mcp` module and no built-in Matrix module. The subprocess never
posts to Matrix directly.

Instead, `manager.py` owns the sole Matrix connection (the bot's `AsyncClient`). Each
turn, the manager runs the subprocess, parses its stream-json output, and posts the
final text back to the room as the bot user (`@harlock`), threaded as a reply to the
triggering message and split into `max_message_length` chunks. Turn errors and
timeouts are surfaced the same way, while verbose detail (stderr, paths) stays in the
PM2 logs only.

Consequences of this model:

- Harlock cannot address arbitrary rooms or users; every reply lands in its own room,
  in-thread with the message that prompted it.
- There is no in-band "send a Matrix message" action for the agent to invoke — output
  is a side effect of finishing a turn, not a tool call.
- Built-in room commands (`!help`, `!recap`, `!sessions`, `!cancel`, `!mirror`) are
  handled directly by the manager and likewise reply via the same relay path.

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

## Rollover QC

A weekly PM2 cron job, `harlock-rollover-qc` (`0 13 * * 0`, Sundays 08:00 EST), scores the past
7 days of rollover notes for quality — a safety net that catches thin or generic summaries before
they degrade Harlock's cross-session continuity.

**Script:** `~/.claude/scripts/harlock-rollover-qc.sh`

1. Skips the Claude QC pass entirely if no `rollover-*.md` notes exist in
   `~/.claude/memory/agents/harlock/working/` for the window — cheap pre-check, no LLM call.
2. Otherwise launches a headless `claude -p` session that reads each rollover note and scores it
   on three dimensions (good / acceptable / poor): topic coverage, decision capture, and detail
   level.
3. Posts a PASS/FAIL summary to `#harlock` via `matrix-mcp`, and maintains a streak counter at
   `~/.claude/memory/agents/sysadmin/harlock-rollover-qc-streak.md` (increments on PASS, resets to
   0 on FAIL or no notes found).

Lock file: `~/.claude/harlock-rollover-qc.lock` (stale after 30 min). Logs to
`~/.claude/logs/harlock-rollover-qc-<date>.log` (60-day retention).

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

Harlock has a dedicated scoped-mcp manifest separate from task-queue agents. The manifest reflects personal assistant use — broad read access, no destructive system operations, and **no Matrix send capability** (see [Matrix integration](#matrix-integration-auto-relay)).

Modules exposed to the subprocess:

| Module | Access | Notes |
|--------|--------|-------|
| `searxng-mcp` | search + fetch | `clear_cache` denied |
| `memsearch-mcp` | hybrid memory search | bearer-token auth |
| `memory-metadata-mcp` | list/filter notes | read-only |
| `graphiti` | knowledge graph | `clear_graph` denied |
| `qmd` | doc search | read-only |
| `githost-mcp` | git read | `git_add`/`git_commit`/`git_push` denied |

There is deliberately no `matrix-mcp` module: Harlock's replies reach Matrix only through the manager's auto-relay, not through a tool the agent can call.
