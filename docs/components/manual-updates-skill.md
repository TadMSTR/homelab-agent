# Manual Updates Skill

**Last updated: 2026-05-07**

`/manual-updates` is an interactive skill for applying or deferring the updates that the nightly updater flagged for manual review — stateful Docker containers, pip globals (memsearch), and npm globals (qmd). It reads pre-fetched changelogs from `updater-state.json` so Ted can work through the queue at his own pace without waiting for live API calls.

## Overview

The 4:30 AM updater (Section H) pre-fetches GitHub release notes for everything in `flag_manual` before Ted wakes up. `/manual-updates` reads that queue and walks through each item one at a time:

1. Shows current → available version, changelog summary, and breaking-change flag
2. Asks: apply / skip (this session) / defer indefinitely / defer until version
3. Dispatches the apply action by item type
4. Moves to the next item

This skill is **claudebox-only** — it requires direct access to Docker, PM2, pip3, npm, and `~/scripts/claude-update.sh`. Do not trigger it in headless or remote contexts.

## Trigger

- `/manual-updates`
- "apply pending updates"
- "what needs updating"
- "work through the update queue"

## Pre-Checks

Before showing any items, the skill verifies:
- No active `claude -p` headless sessions (to avoid disrupting running agents)
- `~/.claude/updater-state.json` exists and has a `pending_manual` key
- No PM2 services in crash-loop (restart count > 10 while online)

If any check fails, it stops and reports the issue without applying anything.

## Apply Actions by Item Type

| Type | Apply action |
|------|-------------|
| Docker container | `docker pull <image>`, then `docker compose -f <file> up -d <service>` using the `compose_services` map in `updater-config.yml` |
| pip global (memsearch) | `pip3 install --upgrade memsearch`, then re-applies all three source patches (ollama.py, \_\_init\_\_.py, core.py) — same patch logic as Section G |
| npm global (qmd) | `sudo /usr/local/sbin/updater-qmd-install.sh` (the sudo wrapper that handles root-owned path + QMD_HOST patch), then `pm2 restart qmd` |

## Defer Options

| Option | Effect |
|--------|--------|
| Skip | Skips this item for the current session only; will appear again next run |
| Defer indefinitely | Sets `deferred: true` — item is hidden from the queue until explicitly un-deferred |
| Defer until version | Sets `defer_until_version: <ver>` — item reappears once that version (or higher) is available, using semver comparison |

Deferral state persists in `updater-state.json`. The Section H pre-fetch preserves existing deferral state on each write.

## Breaking Changes

Items where Section H detected breaking-change keywords are flagged `[BREAKING]` in the queue display. The skill highlights these and recommends reading the full release notes before applying. Items where changelog fetch failed are flagged `[changelog unavailable]`.

## State File Location

`~/.claude/updater-state.json` — the `pending_manual` key maps item names (container names or package names) to their entry:

```json
{
  "pending_manual": {
    "grafana": {
      "type": "docker",
      "current_version": "10.4.0",
      "available_version": "11.0.0",
      "breaking_changes": true,
      "changelog_summary": "...",
      "deferred": false
    }
  }
}
```

## Related

- [updater.md](updater.md) — the nightly updater that populates `pending_manual` (Section H)
- `updater-config.yml` — `changelog_urls` map and `compose_services` map used during apply
- `/usr/local/sbin/updater-qmd-install.sh` — sudo wrapper for qmd npm installs
