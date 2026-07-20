# memory-compact-qc

Weekly quality check on `memsearch compact` output — the safety net for the 2026-07-13 switch
of the daily compact step from the Anthropic API to a local Ollama model (`qwen3:4b`), run to cut
pay-per-use cost. Spot-checks compact summaries against their raw session sources and flags
quality drift before it silently degrades distilled memory.

- **Script:** `~/scripts/memory-compact-qc.sh`
- **Schedule:** PM2 cron, Sundays at 14:00 UTC (`0 14 * * 0`)
- **Log:** `~/.claude/logs/memory-compact-qc-<date>.log` (60-day retention)
- **No listening port** — runs as a batch job

## How It Works

1. Cheap pre-check: counts `~/.claude/memory/shared/compact/memory/*.md` files modified in the
   past 7 days. If none, skips the Claude QC pass entirely, posts a "no compact output" alert to
   `#sysadmin`, and resets the streak counter.
2. Otherwise launches a headless `claude -p` session (Sonnet, 600s timeout) that:
   - Reads each compact output file in the window
   - Finds the raw session source(s) it was generated from (`.memsearch/memory/<date>.md` across
     all project dirs) and reads those too
   - Scores each compact file on three dimensions (good / acceptable / poor) against its raw
     source: topic coverage, decision capture, and detail level (including hallucinated content
     not present in the source)
   - Flags in output if more than 10 compact files were found in the window
3. Determines PASS (no dimension rated poor across any file) or FAIL (at least one poor rating)
4. Posts the result to `#sysadmin` via `matrix-mcp send_matrix_message`
5. Updates a streak counter at `~/.claude/memory/agents/sysadmin/memory-compact-qc-streak.md`
   (increments on PASS, resets to 0 on FAIL or no files found)
6. Logs a `compact_qc.complete` event to agent-bus with streak, file count, and result

## Configuration

| Setting | Value |
|---------|-------|
| Compact output dir | `~/.claude/memory/shared/compact/memory/` |
| Streak file | `~/.claude/memory/agents/sysadmin/memory-compact-qc-streak.md` |
| Lock file | `~/.claude/memory-compact-qc.lock` (stale after 30 min) |
| Model | Sonnet, `claude -p --dangerously-skip-permissions` |
| Timeout | 600s |
| Alert room | `#sysadmin` |
| Flag threshold | more than 10 compact files in the 7-day window |

## Dependencies

- **memsearch-compact** — the `memory-pipeline` cron step (`0 4 * * *`) that this QC checks the output of; runs on Ollama `qwen3:4b` since 2026-07-13
- **system-ops** — `read_directory`/`read_file` used to read compact output and raw session sources
- **matrix-mcp** — posts PASS/FAIL results to `#sysadmin`
- **agent-bus** — QC completion events

## Operations

```bash
# Check last run
pm2 show memory-compact-qc

# View log
tail -40 ~/.claude/logs/memory-compact-qc-$(date +%Y-%m-%d).log

# Trigger manual run
pm2 restart memory-compact-qc

# Check current streak
cat ~/.claude/memory/agents/sysadmin/memory-compact-qc-streak.md

# Check for a stuck lock
ls -la ~/.claude/memory-compact-qc.lock
```

## Related Docs

- [memory-services.md](memory-services.md) — memory pipeline overview, including `memory-pipeline` (memsearch-compact + qmd-refresh)
- [memory-architecture.md](memory-architecture.md) — three-tier memory design
