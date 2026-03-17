# Doc-Health

Doc-health is an automated documentation audit agent. A headless Claude Code session runs weekly as a PM2 cron job, checks for documentation drift, missing index entries, undocumented services, stale project instructions, and leaked secrets in the public repo. It produces a report with findings and auto-fixes only index.md entries.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) of the architecture alongside memory-sync. Where memory-sync handles knowledge capture (sessions to persistent memory), doc-health handles documentation hygiene (keeping docs accurate, complete, and sanitized).

## Why Doc-Health

Documentation drift happens gradually. A service gets added but the component doc doesn't get written. An IP address slips into the public repo. A project instruction file references infrastructure that changed two months ago. These issues are caught reactively — someone notices mid-session and fixes it manually.

Doc-health runs the same checks an attentive reviewer would, on a schedule, so drift doesn't accumulate.

## The 7 Checks

### 1. Drift Detection
Resolves CLAUDE.md symlinks under the Claude Code projects directory and compares content against source files in the context repo. Flags content mismatches and regular files that should be symlinks.

### 2. Index Health
Verifies every path in the context repo's `index.md` exists on disk. Reverse-checks for files on disk that aren't in the index. **Auto-fixes:** adds missing index entries and commits them.

### 3. Coverage Gaps
Parses `pm2 jlist` and `docker ps` for running services, checks each against component docs. Searches inside docs for service mentions — not just filename matching — since some services are documented within another component's doc.

### 4. Staleness
Checks project instruction files for last-modified date via git log. Flags files older than 30 days that reference infrastructure components with recent changes.

### 5. Recent Updates Drafting
Pulls the last 7 days of git history across repos and drafts candidate bullet points for the README "Recent Updates" section. Suggestions only — human curates.

### 6. Sanitization Scan
Scans the public repo for internal IPs, real domains, tokens, and API keys. Reports file path and line number for each finding.

### 7. Structural Integrity
Verifies CLAUDE.md files and skill SKILL.md files are structurally sound — catches silent behavioral degradation before an agent acts on broken instructions.

For CLAUDE.md files, checks that symlinks resolve to real non-empty files, and that interactive agents have the required sections (`## On Session Start`, `## Scope` or `## Purpose`, `## Memory`). Also verifies that memory paths listed under `Read from:` and `Write to:` actually exist on disk.

For skill SKILL.md files, checks that frontmatter is present with non-empty `name` and `description` fields, and that descriptions are at least 80 characters — shorter descriptions won't reliably trigger the skill from the tool list.

## Report Output

The report overwrites `~/.claude/memory/shared/doc-health-report.md` on each run. Findings are tagged with severity:

- **action-needed** — requires human attention
- **warn** — potential issue, review recommended
- **info** — status confirmation, no action needed

The report has a 14-day expiry in its frontmatter. The next run overwrites it anyway, so stale reports self-identify.

## Runtime

Two PM2 services run doc-health on different schedules with different scopes:

**Weekly full scan (`doc-health`):**
- **Schedule:** Sundays at 11:00 PM (`0 23 * * 0`)
- **Model:** Opus (strongest reasoning for staleness cross-referencing and sanitization judgment)
- **Checks:** All 7
- **Timeout:** 20 minutes
- **Output:** `~/.claude/memory/shared/doc-health-report.md`

**Nightly targeted scan (`doc-health-daily`):**
- **Schedule:** 10:00 PM daily (`0 22 * * *`)
- **Model:** Sonnet
- **Checks:** 1, 2, 6, 7 (drift, index, sanitization, structural integrity)
- **Scope:** Only files listed in `~/.claude/memory/shared/daily-touched-files.json`
- **Skips entirely** if no files were touched that day — zero cost on quiet days
- **Output:** `~/.claude/memory/shared/doc-health-targeted-report.md`

Both services share:
- **Lock file:** `~/.claude/doc-health.lock` (stale after 20 minutes)
- **Script:** `~/.claude/scripts/doc-health.sh` (full run = no args, targeted = `--targeted`)
- **Agent instructions:** `claude-projects/doc-health/CLAUDE.md` in the context repo

## Writer Feedback Loop

The weekly scan and the writer agent form a closed loop for keeping docs current after infrastructure builds:

1. A building agent (claudebox, dev) completes work and appends the affected files to `~/.claude/memory/shared/daily-touched-files.json`.
2. The writer agent processes the doc-update queue, applies auto-fixes, and appends its own modified files to `daily-touched-files.json`.
3. The writer triggers a targeted re-scan: `bash ~/.claude/scripts/doc-health.sh --targeted &`.
4. The targeted scan runs checks 1/2/6/7 scoped to only the touched files, confirms fixes landed cleanly, and emits `scan_type=targeted` events to InfluxDB.
5. The nightly `doc-health-daily` cron picks up any remaining touched files at 10 PM, then resets `daily-touched-files.json`.

The `scan_type` tag on InfluxDB events distinguishes full-scan findings from targeted re-scan confirmations in Grafana, so you can tell at a glance whether a finding is new or a follow-up check.

## Design Constraints

Doc-health is report-first by design:

- **No documentation rewrites** — that's a human or doc-designer task
- **No new component docs** — those need editorial decisions about scope and structure
- **No memory file changes** — memory-sync's domain
- **Only auto-commits index.md fixes** — mechanical corrections with clear right answers

Git operations use `pull --rebase` before committing and abort on merge conflicts rather than forcing.

## Relationship to Other Agents

| Agent | Domain | Overlap |
|-------|--------|---------|
| memory-sync | Knowledge capture (session → working → distilled) | None — doc-health doesn't touch memory files |
| doc-designer (skill) | Documentation rewrites and redesigns | Doc-health finds problems; doc-designer fixes them |
| homelab-agent-writer (skill) | New component docs | Doc-health flags coverage gaps; the writer fills them |
| librarian (skill) | Context repo sync and index maintenance | Doc-health's index check overlaps; librarian is manual, doc-health is automated |

## Related Docs

- [Memory Sync](memory-sync.md) — the other automated Layer 3 agent
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — cron schedule and service definition
