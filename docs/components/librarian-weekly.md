# librarian-weekly

librarian-weekly is a Monday morning PM2 cron job that keeps the prime-directive repository in sync with actual system state. It runs the librarian skill as a headless Claude Code agent, compares what's in the repo against semantic memory and recent activity, and commits any missing or stale content.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) alongside the memory pipeline jobs as part of the automated maintenance layer.

## What It Does

Each Monday at 6:00 AM:

1. Loads `index.md` from the prime-directive repo
2. Checks basic-memory and qmd for recent activity (7–14 days)
3. Identifies drift: skills on disk not in the repo, index entries pointing to missing files, stale metadata
4. Commits any missing skill files and updates `index.md`
5. Fires an ntfy notification on completion or failure

The job is intentionally narrow — it handles mechanical sync, not strategic decisions. If it finds something that requires judgment (a skill that changed significantly, a note that conflicts with repo content), it flags it in the notification rather than auto-committing.

## Runtime

- **PM2 service:** `librarian-weekly`
- **Schedule:** Mondays 6:00 AM (`0 6 * * 1`)
- **Script:** `~/.claude/scripts/librarian.sh`
- **Log:** `~/.claude/logs/librarian-YYYY-MM-DD.log`
- **Model:** Sonnet

## Manual Run

```bash
bash ~/.claude/scripts/librarian.sh
```

Or trigger via PM2:
```bash
pm2 trigger librarian-weekly run
```

## What Gets Auto-Committed

- Skill files that exist on disk but are missing from the repo
- `index.md` entries for skills, notes, or docs that exist on disk but aren't indexed
- Updated `index.md` date when entries are added

## What Gets Flagged (Not Auto-Committed)

- Skills or docs that changed significantly and may need human review
- Conflicts between memory content and repo content
- Items that exist in memory but have no clear home in the repo

## Relationship to the Librarian Skill

The `librarian` skill (used in interactive sessions) and librarian-weekly run the same logic. The difference is context: the weekly job runs headless on a fixed schedule with no human in the loop. The interactive skill is used for deeper maintenance sessions where Ted can approve scope and review proposed changes before commit.

Both share the same script — `librarian.sh` invokes the librarian skill via Claude Code.

## Observability

- ntfy notification fires on job completion (success or failure)
- Commit messages use the prefix `librarian-weekly:` for easy filtering in git log
- PM2 logs: `pm2 logs librarian-weekly`

## Related Docs

- [Memory pipeline](memory-pipeline.md) — the other scheduled maintenance jobs that run on a similar cadence
- [Prime directive repo](../../README.md) — what the librarian maintains
