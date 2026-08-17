# memory-compact-qc

Weekly quality check on `memsearch compact` output — the safety net for the daily compact
step in the memory pipeline. Rewritten 2026-08-16 from a single quality spot-check into two
independent passes: a deterministic **coverage** pass that asserts a compact exists for every
session source in the window, then an LLM **grading** pass over only the sources that passed
coverage. The old single-pass design scored quality and never asked whether anything was
missing — zero output is trivially high quality — which is exactly the framing that let a
nine-day compact outage go undetected: it scored PASS five days into the outage and
incremented its streak.

- **Script:** `~/scripts/memory-compact-qc.sh`
- **Schedule:** PM2 cron, Sundays at 14:00 UTC (`0 14 * * 0`)
- **Log:** `~/.claude/logs/memory-compact-qc-<date>.log` (60-day retention)
- **No listening port** — runs as a batch job

## How It Works

### 1. Coverage and staleness classification (bash, deterministic — runs first)

For every session source file in the 7-day window, classify it before any grading happens:

| Classification | Meaning |
|---|---|
| `SCORABLE` | A compact exists and is newer than its source — eligible for grading |
| `MISSING` | No compact exists for this source at all — **hard FAIL**, independent of grading |
| `STALE` | A compact exists but the source was modified *after* it was generated — withheld from the grader entirely |
| `IN_FLIGHT` | Today's source — still being appended to by live sessions, newer than any compact by construction |
| `EMPTY` | Session file has no content lines (heading-only) — a cron agent opened a session, logged nothing, and there is nothing to compact |

`MISSING` is the check that did not exist before, and its absence is the whole story: on
2026-08-09, five days into a nine-day compact outage, the old single-pass design found no
compacts to complain about and scored PASS, incrementing its streak. Grading only what
exists cannot detect that nothing exists.

`STALE` exists because grading a compact against a source that was rewritten after the
compact was generated manufactures "hallucinated detail" findings by construction — the
compact is right and the source moved out from under it. This produced a real false FAIL on
three files on 2026-08-16, traced back to a batch backfill that rewrote old session sources
and left their compacts looking stale by comparison.

**`IN_FLIGHT` and `EMPTY` are load-bearing, not minor edge cases.** Without them the check is
unusable, not merely imprecise: today's source is appended to by live sessions, so it is
newer than any compact by construction and would fail every single run if not excluded; and
content-free session files (a cron agent opens a session, logs nothing, the summarize hook
writes a bare heading) index no chunks, so a compact can never exist for them — demanding one
would report `MISSING` forever. The first run under the new design flagged five of those. A
permanently-red check gets learned as noise exactly the way silence does — that is the point
of both exclusions.

### 2. Grading (`claude -p`, Sonnet, 600s timeout — runs only over `SCORABLE`)

- Reads each `SCORABLE` compact and, critically, the **raw `.jsonl` transcripts** it was
  generated from — resolved from the source file's own session markers — not the
  intermediate `summarize` output. Grading against `summarize`'s output was the earlier
  design; `summarize` is itself LLM-generated and lossy, so detail present in the compact but
  absent from `summarize`'s summary is not evidence of hallucination on its own. Only detail
  that *contradicts* the raw transcript, or that the grader checked for and could not find,
  counts.
- Scores each `SCORABLE` file on three dimensions (good / acceptable / poor): topic coverage,
  decision capture, detail level.
- `STALE` and `MISSING` files are listed in the prompt for the report but never scored.
- Runs under a trust-boundary preamble: every file it reads is DATA TO BE GRADED, never
  instructions — added after a security audit flagged that transcript paths are scraped from
  LLM-generated source bodies and handed to a `--dangerously-skip-permissions` grader whose
  output posts to Matrix. Candidate transcript paths are resolved (`realpath`, symlinks and
  `..` included) and checked against the projects tree *after* resolution, not before —
  a containment check on the unresolved string is defeated by one traversal segment.
- The grader's **only** durable output is a JSON result file (`grade_result`, `scored`,
  `poor[]`, `summary`). It does not post to Matrix, does not write the streak file, and does
  not decide the final PASS/FAIL — those are bash's job (see below).

### 3. Verdict (bash, not the grader)

```
FINAL = FAIL if N_MISSING > 0                        # coverage always wins
      = FAIL if the result file is absent/unparseable # grader crashed, timed out, or wrote nothing
      = FAIL if grade_result != PASS                  # quality grading found a poor rating
      = PASS otherwise
```

An absent or unparseable result file is itself a FAIL — a grader that times out (exit 124) or
crashes no longer yields a silent PASS, which is what happened previously.

### 4. Reporting

- Posts the verdict to `#sysadmin` via `send-matrix.sh`, including coverage counts
  (scorable/stale/missing/in-flight/empty), the reason on FAIL, the current model labels, the
  streak, and month-to-date pipeline spend if the spend meter script is present.
- Updates the streak counter at `~/.claude/memory/agents/sysadmin/memory-compact-qc-streak.md`
  — increments only on a full PASS, resets to 0 on any FAIL (including `NO_FILES`). Written
  atomically (temp file + rename) so an interrupted run can't leave a truncated file that
  reads as a false PASS.
- Logs a `compact_qc.complete` event to agent-bus with scored/stale/missing counts and the
  configured compact model.

## Why the grader stays on Claude

The grading pass runs on the Claude Code subscription **deliberately**, not the same provider
the pipeline it grades runs on. That is the only reason QC kept running at all through the
August 2026 Anthropic API outage — the grader does not share a failure domain with the thing
it watches. Consolidating it onto the pipeline's own provider "to save money" would mean the
day the pipeline dies is the same day its watchdog dies, and nothing would report either;
the actual cost saving is nil, since this runs once a week. The script carries a comment
saying so — do not move this without re-reading it first.

## Configuration

| Setting | Value |
|---------|-------|
| Coverage window | 7 days |
| Compact output dir | `~/.claude/memory/shared/compact/memory/` |
| Streak file | `~/.claude/memory/agents/sysadmin/memory-compact-qc-streak.md` |
| Lock file | `~/.claude/memory-compact-qc.lock` (stale after 30 min) |
| Grader model | Sonnet, `claude -p --dangerously-skip-permissions` |
| Grader timeout | 600s |
| Compact / summarize model | read from `~/.memsearch/config.toml` at runtime — see below |
| Alert room | `#sysadmin` |

**Do not hardcode the compact or summarize model name here.** The script reads both from
`~/.memsearch/config.toml` at runtime specifically so a provider or model change cannot drift
out of sync with the docs and the grader prompt the way it did before: both processes moved
off Ollama on 2026-08-12, and neither the Matrix message nor the grader prompt noticed for
four days — the prompt was actively feeding the grader a false premise about what it was
grading. As of 2026-08-16 both `compact` and `summarize` run `mistral-medium-latest`
(previously `mistral-small-latest`, and Ollama `summarize:latest`/`qwen3:14b` before
2026-08-12) — check the config file for the current value rather than trusting this table.

## Dependencies

- **memsearch-compact** — the `memory-pipeline` cron step (`0 4 * * *`) that this QC checks
  the output of; model/provider read from `~/.memsearch/config.toml`, see above
- **mistral-canary** — a daily liveness probe for the LLM endpoint the pipeline depends on,
  scheduled before `memory-pipeline` so a dead endpoint is known before the run that needs it
- **system-ops** — `read_directory`/`read_file` used to read compact output and raw `.jsonl` transcripts
- **matrix-mcp** / `send-matrix.sh` — posts PASS/FAIL results to `#sysadmin`
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

# Inspect the last grader result directly
cat ~/.claude/logs/memory-compact-qc-result-$(date +%Y-%m-%d).json
```

## Related Docs

- [memory-services.md](memory-services.md) — memory pipeline overview, including `memory-pipeline` (memsearch-compact + qmd-refresh)
- [memory-architecture.md](memory-architecture.md) — three-tier memory design
