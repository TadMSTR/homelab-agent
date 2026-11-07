# doc-health and kb-lint

Forge checks its documentation in two layers, following one rule: **a script wherever a
script fits, and an LLM only for the judgment that is left.**

| Layer | What | When | Cost |
|---|---|---|---|
| **kb-lint** | `kb-lint.py`, a deterministic checker driven by a rule file | daily 06:10 (`--full`) and on every push to the knowledge-base and runbooks repos (`--static`) | no tokens |
| **doc-health** | a headless Claude (Opus) session | weekly, Sundays 23:00 | one LLM run |

kb-lint does every mechanical check. doc-health runs kb-lint first, receives its JSON as data,
and does only what needs reading comprehension.

## kb-lint

- **Script:** `host-forge-scripts/scripts/kb-lint.py`
- **Rules:** `host-forge-scripts/scripts/config/kb-lint.yml`
- **Output:** `~/.claude/memory/shared/kb-lint/latest.json` plus a dated copy (30 days), and
  `kb_lint.prom` for Prometheus

### Checks

| Id | Check | Mode |
|---|---|---|
| S1 | Relative links resolve | static |
| S2 | Frontmatter (runbooks; skill `SKILL.md` name + description of at least 80 chars) | static |
| S3 | `**Last updated: YYYY-MM-DD**` present, parseable, not in the future | static |
| S4 | No duplicate key rows in a table the rule file reads | static |
| S5 | Ticket references follow the `#N (id M)` rule (reuses `ticket-ref-lint.py`) | static |
| S6 | Public repos: no internal IPs or private domains (regex), no secrets (gitleaks, redacted) | static |
| S8 | This repo's `index.md` lists every component doc, and every path it names exists | static |
| C1 | Every doc matches a class in the rule file | static |
| H1 | PM2 tables match `pm2 jlist` (both directions) | full |
| H2 | The cron table matches the crontab's `hc-run.sh` slugs (both directions) | full |
| H3 | The stack inventory matches Docker's compose projects (both directions) | full |
| H4 | Ports in the port registry are listening | full |
| H5 | Host paths named in runbooks and current-state docs exist | full |
| H6 | The qmd index: no orphaned collections, counts match disk, nothing stale | full |
| S7 | Each agent's project `CLAUDE.md` is a symlink to its source | full |

### Section-aware, from a rule file

A generic scan over-reports: a prototype flagged 61 cron rows as "not running PM2 apps"
before it read each doc's sections separately. So every host check names a doc, a heading,
the table's exact header row and its key column. Docs are classed as `current-state`,
`reference`, `history` (build records, checked for links only) or `procedure`. Only
current-state docs are compared with the live host.

A row is exempt from "must be live" only if its **bold** text says so (for example
"**`stopped`, deliberately**"). If an exempt thing turns out to be live, that's reported
too, as a stale exemption.

### Exit codes, and why gap matters most

`0` clean, `1` findings, `2` usage or crash, `3` **gap**.

A gap means an input could not be read. Examples: a heading or table the rule file names is
gone, PM2 returned 0 apps, `pm2` is not on PATH, the qmd index is unreadable. Gap takes
precedence over findings. **An empty input must never read as "nothing to report."** That is
how the old nightly LLM scan died, twice. It read a tracker file that no agent wrote any
more, and it exited 0 every night for months.

### Secrets

`pm2 jlist` carries every app's environment, and crontab lines can carry arguments. kb-lint
parses both in memory and keeps only the fields a check needs: app name and status, cron
slug, compose project, port number. No raw input or subprocess error output reaches any
output. A test plants a canary secret in each source and asserts it appears nowhere.

### Metrics and alerts

`kb_lint.prom` goes to its own textfile directory. A dedicated Alloy
`prometheus.exporter.unix` component (textfile collector only) serves it, and a hardened
Prometheus job `kb_lint` scrapes it. The Grafana dashboard **Knowledge base health** shows:

- the share of current-state docs verified against the live host (docs no check can verify
  are counted separately, so the percentage is honest);
- findings by check, with a fixed colour and glyph per check family;
- a heartbeat: time since the last good run, and rows checked per section.

Alerts:

- `KbLintStale`: no good run in 26 h.
- `KbLintDeadInput`: a gap, or a section that checked 0 rows.
- `KbLintTextfileError`

These sit alongside the Healthchecks cron-liveness check, which only sees that the job
exited. Findings never alert: they are documentation debt for the writer.

## doc-health

- **Script:** `~/.claude/scripts/doc-health.sh` (cron, Sundays 23:00, wrapped in `hc-run.sh`)
- **Project dir:** `~/.claude/projects/doc-health`
- **Model:** Opus
- **Report:** `~/.claude/memory/shared/doc-health-report.md` (overwritten each run)

### How it works

1. Takes a lock and checks that its scoped-mcp connection is ready.
2. Runs `kb-lint.py --full`. On a gap or crash it aborts **before** launching Claude, posts
   to the alerts room and exits non-zero. It won't spend an Opus run on a broken input.
3. Passes kb-lint's JSON into the prompt as a delimited data block, marked as data, not
   instructions. `<` is escaped so no quoted doc text can close the block.
4. Claude does the judgment checks:
   - **kb-lint findings → writer tasks.** One task per (repo, check) with errors, and one
     batched task for warnings. Findings that need a decision rather than an edit go to the
     report instead.
   - **Coverage:** whether each running service is actually explained somewhere, not just
     listed.
   - **Staleness:** docs that describe something that changed recently.
   - **Contradictions:** the same fact stated differently in two current-state docs.
   - **README "Recent Updates" drafting:** suggestions only.
5. Writes the report, quotes kb-lint's summary counts in it, and notifies the announcements
   room (alerts room if anything needs action).

Writer work goes through the task queue (`task_type: docs`). Nothing is auto-committed.

### History

- **2026-03:** built with a weekly 7-check Opus scan and a nightly Sonnet "targeted" scan of
  files agents listed in a tracker file.
- **2026-11-06:** the nightly scan was retired. The tracker had not been written since
  2026-08-15, and the scan exited 0 every night ("no files touched"). That was its second
  silent multi-month outage. Checks 1 (drift), 2 (index), 6 (sanitization) and 7
  (structure), and the mechanical half of 3 (coverage), moved to kb-lint.

## Operations

```bash
# What does the knowledge base look like right now? (writes nothing)
~/scripts/kb-lint.py --full --no-write --format text

# Lint one repo the way CI does
~/scripts/kb-lint.py --static --repo <checkout> --kind knowledge-base --format text

# Last daily result
python3 -m json.tool ~/.claude/memory/shared/kb-lint/latest.json | head -40

# doc-health logs and report
tail -30 ~/.claude/logs/doc-health-$(date +%Y-%m-%d).log
head -20 ~/.claude/memory/shared/doc-health-report.md
```

## Related Docs

- [healthchecks](../observability/healthchecks.md): cron liveness for both jobs
- system-agents: agents that act on doc-health findings
