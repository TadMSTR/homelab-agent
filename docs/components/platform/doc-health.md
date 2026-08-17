# doc-health

doc-health is a documentation health audit system that runs as two PM2 services: a weekly
full scan (Opus) and a nightly targeted scan (Sonnet). It launches headless Claude sessions
to check for documentation drift, staleness, coverage gaps, and structural issues, then
writes findings to the doc queue for the writer agent to process.

- **Script:** `~/.claude/scripts/doc-health.sh`
- **Project dir:** `~/.claude/projects/doc-health`
- **No listening port** — runs as scheduled batch jobs

## PM2 Services

| Service | Schedule | Model | Timeout | What it does |
|---------|----------|-------|---------|-------------|
| `doc-health` | Sundays 23:00 (`0 23 * * 0`) | Opus | 20 min | Full 7-check audit across all docs |
| `doc-health-daily` | Nightly 22:00 (`0 22 * * *`) | Sonnet | 10 min | Targeted scan of files touched that day |

## Audit Checks

The full scan runs all 7 checks. The targeted scan runs only checks 1, 2, 6, and 7
(scoped to files listed in `daily-touched-files.json`).

| # | Check | Full | Targeted |
|---|-------|------|----------|
| 1 | Drift detection — symlinked project instructions | yes | yes |
| 2 | Index health — component docs and index files | yes | yes |
| 3 | Coverage gaps — undocumented services | yes | no |
| 4 | Staleness — docs not updated recently | yes | no |
| 5 | Recent updates drafting | yes | no |
| 6 | Sanitization — secrets in config/proxy files | yes | yes |
| 7 | Structural integrity — CLAUDE.md/SKILL.md validation | yes | yes |

## Reports

| Mode | Report path |
|------|-------------|
| Full | `~/.claude/memory/shared/doc-health-report.md` |
| Targeted | `~/.claude/memory/shared/doc-health-targeted-report.md` |

Reports are overwritten each run. Findings that require doc updates are submitted to the
task queue (`task_type: docs`, one task per doc) rather than appended to a queue file — the
flat `~/.claude/memory/shared/doc-update-queue.jsonl` this used to write was retired
2026-08-16. `action-needed` findings (checks 3 and 4) become one task each; `warn`-level
coverage gaps are collapsed into a single batched task per run rather than one task per
finding, so a run surfacing several minor gaps doesn't dump a double-digit burst into the
writer's queue.

## Configuration

| Setting | Value |
|---------|-------|
| Lock file (full) | `~/.claude/doc-health.lock` |
| Lock file (targeted) | `~/.claude/doc-health-targeted.lock` |
| Touched files tracker | `~/.claude/memory/shared/daily-touched-files.json` |
| Log dir | `~/.claude/logs/` |
| Log retention | 30 days (auto-cleanup) |
| Stale lock threshold | 20 min (full), 15 min (targeted) |

## How It Works

1. Acquires a lock file (removes stale locks automatically)
2. Targeted mode: checks `daily-touched-files.json` — skips if no files touched today
3. Launches `claude -p` with the doc-health project CLAUDE.md and relevant source directories
4. Claude runs the audit checks and writes the report
5. Sends a Matrix notification to the `agents` room with the result summary
6. Targeted mode: resets `daily-touched-files.json` after completing

## Dependencies

- **matrix-mcp** (port 8487) — sends completion/failure notifications
- **daily-touched-files.json** — populated by other processes to track which files changed
- **doc-health project** (`~/.claude/projects/doc-health/CLAUDE.md`) — audit instructions

## Operations

```bash
# Check service status
pm2 show doc-health
pm2 show doc-health-daily

# View logs
ls ~/.claude/logs/doc-health*.log
tail -30 ~/.claude/logs/doc-health-$(date +%Y-%m-%d).log

# Force a targeted scan
pm2 restart doc-health-daily

# Force a full scan
pm2 restart doc-health

# Check for stuck locks
ls -la ~/.claude/doc-health*.lock

# View latest reports
head -20 ~/.claude/memory/shared/doc-health-report.md
head -20 ~/.claude/memory/shared/doc-health-targeted-report.md
```

## Related Docs

- system-agents — agents that act on doc-health findings
