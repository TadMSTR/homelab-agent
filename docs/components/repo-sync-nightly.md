# repo-sync-nightly

repo-sync-nightly is a PM2 cron job that runs nightly repo hygiene across all personal repos. It auto-commits and pushes agent-generated changes in doc repos, and sends an ntfy alert for code repos that have uncommitted or unpushed work.

## What It Does

Runs at 23:30 daily and scans every repo under `~/repos/personal/`. For each repo with pending changes, it applies one of two policies based on whether the repo is classified as a doc repo or a code repo:

**Doc repos — auto-commit and push.** Uncommitted changes are assumed to be agent-generated documentation edits. The job commits them with a timestamped message (`chore: agent sync YYYY-MM-DD [repo-sync]`) and pushes. No human review needed.

**Code repos — alert only.** Uncommitted changes or unpushed commits trigger an ntfy notification. The job never auto-commits code. The alert lists each affected repo and what's pending.

## Doc Repos (Auto-Committed)

| Repo | Why auto-commit is safe |
|------|------------------------|
| `claude-prime-directive` | Agent-maintained config and skill files |
| `helm-platform` | Build docs written by helm-build agent |
| `homelab-agent` | Docs written by writer agent |
| `prime-directive-docs` | Documentation only |
| `grafana-dashboards` | Dashboard JSON written by agents |
| `blog` | Draft posts written by agents |
| `TadMSTR` | Profile README written by agents |

All other repos are treated as code repos.

## Runtime

- **PM2 service:** `repo-sync-nightly` (ID 24)
- **Schedule:** 23:30 daily (`30 23 * * *`)
- **Script:** `~/scripts/repo-sync.sh`
- **Log:** `~/.claude/logs/repo-sync.log`

## Alert Behavior

ntfy fires to `claudebox-alerts` when:
- Any code repo has uncommitted changes or unpushed commits
- Any doc repo fails to commit or push (logged as an error)

Alert title: `[repo-sync] Pending changes need attention`

No alert is sent if everything is clean or if only doc repos had changes (those are handled silently).

## Manual Run

```bash
bash ~/scripts/repo-sync.sh
```

## Gotchas

**Auto-commit uses `git add -A`.** All untracked and modified files in a doc repo are staged. If a partially-written file lands in a doc repo mid-session, it will be committed as-is. The 23:30 schedule is intentional — it runs after the writer's typical working window.

**Push failures are logged but don't retry.** If a push fails (remote conflict, network issue), the committed changes stay local until the next run or a manual push. The ntfy alert fires on push failure so it doesn't go unnoticed.

**Code repos accumulate.** The alert fires every night until the pending changes are dealt with. If you're mid-feature and don't want nightly alerts, push a WIP commit.

## Related Docs

- [memory-pipeline](memory-pipeline.md) — the other nightly jobs running in the same window
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — service definition
