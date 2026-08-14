# plugin-drift-sentinel

Detects drift on forked Claude Code plugin marketplaces and alerts — it never repairs.
Written after an incident (vikunja#250/#251) where a fork without a pinned `ref` was
silently re-cloned from upstream onto its default branch by the CLI, reverting five
carried patches with no log line and no error, hidden for a day.

## Why it exists

`known_marketplaces.json` is a derived cache, not the source of truth. The real
declaration lives in `settings.json` under `extraKnownMarketplaces`, and Claude Code
re-applies it at every session startup. Source identity includes `ref` — a fork
declared without one is drift waiting to happen. This script checks the whole chain
(declaration → registry → checkout → installed cache) on every run.

## What it asserts

Per forked marketplace, in order:

| Assertion | Checks |
|-----------|--------|
| `declaration` | `settings.json` declares the expected `repo` **and** `ref`. Load-bearing — without it, a settings.json reverted to upstream would still satisfy `registry` (both sides agreeing on the wrong value), which is precisely the bug this exists to catch. |
| `registry` | `known_marketplaces.json` agrees with `settings.json` on `repo` + `ref`. |
| `checkout_origin` | The git checkout's `origin` remote points at the expected repo. |
| `checkout_branch` | The checkout sits on the expected ref. |
| `cache_content` | The installed plugin cache is byte-for-byte identical to the checkout's plugin source tree (SHA-256 per file, executable bit included, symlinks compared by target and never followed), excluding `.in_use`, `__pycache__`, `.git`, and `*.pyc`. |

`gitCommitSha` (from `installed_plugins.json`) is reported at INFO as provenance, not
asserted. Nothing writes it, so it goes stale on its own and says nothing about whether
the installed files are actually right — `cache_content` is what holds the line.

### Why content, not a recorded SHA (vikunja#381)

`cache_content` replaced an earlier `checkout_head` assertion that compared
`installed_plugins.json`'s `gitCommitSha` against `git rev-parse HEAD`. That broke
constantly: HEAD moves for *any* commit anywhere in the repo, not just the plugin
subtree, so a change with several commits in flight would false-alarm daily. It was
also weaker for the incident it exists to catch — a recorded SHA nobody updates still
matches even after the underlying files are replaced by a re-clone. Content cannot lie
that way, and it needs no new bookkeeping: both sides are already on disk.

## Two operational gotchas

1. **`~/.claude/plugins/marketplaces/memsearch-plugins` is a symlink**, not a checkout,
   pointing at the live `~/repos/personal/memsearch` working tree. The sentinel
   compares against whatever is currently on disk there, so it also fires on an
   **uncommitted edit** under `plugins/claude-code/` in that working tree. That's a
   true positive, not a bug — but expect it to speak up mid-edit during a fork upstream
   sync if the sync touches the plugin subtree.
2. **It never repairs, by design.** Silent self-healing is what let the original #250
   incident hide for a day. A `cache_content` failure needs a human to re-sync the
   cache; the script will alert every run until that happens.

`installPath` (read from `installed_plugins.json`, which is exactly the state this
sentinel exists to distrust) is constrained to resolve under the plugin cache root
before anything walks it — a prerequisite check, not a drift assertion (audit LOW,
resolved). Anything that makes a comparison impossible — missing checkout, unreadable
manifest, a plugin no longer declared in `marketplace.json` — is treated as a failure,
never a silent pass.

## Configuration

`scripts/plugin-drift-sentinel.config.json` (same directory as the script):

| Key | Meaning |
|-----|---------|
| `paths.settings` | Path to `settings.json` |
| `paths.known_marketplaces` | Path to `known_marketplaces.json` |
| `paths.installed_plugins` | Path to `installed_plugins.json` |
| `paths.marketplaces_dir` | Marketplace checkouts directory |
| `paths.cache_root` | Directory every `installPath` must resolve under (defaults to `marketplaces_dir`'s sibling `cache`) |
| `matrix.script` / `matrix.room` | Alert delivery — defaults to `#alerts` |
| `forked_marketplaces.<name>.expected_repo` / `.expected_ref` / `.plugins` | One entry per forked marketplace to track |

Add an entry under `forked_marketplaces` for any marketplace pinned to a fork rather
than tracking upstream — nothing else needs to change.

## Operations

Runs from `memory-pipeline.sh` step 0, the 04:00 cron. On drift it alerts to `#alerts`
and the pipeline continues (drift is surfaced, not fatal to the rest of the run).

```bash
# Manual run
/home/ted/scripts/plugin-drift-sentinel.py

# Report only, skip the Matrix alert
/home/ted/scripts/plugin-drift-sentinel.py --no-alert
```

Exit codes: `0` all assertions passed, `1` drift detected (alert sent), `2`
config/IO error (e.g. config file or plugin state unreadable).

## Dependencies

- `settings.json`, `known_marketplaces.json`, `installed_plugins.json` — Claude Code's
  own plugin state, read-only
- `send-matrix.sh` — alert delivery to `#alerts`
- 29-assertion test suite in the same repo, `host-forge/scripts` main

## Related

- vikunja#250/#251 — the incident that motivated this script
- vikunja#381 — `checkout_head` → `cache_content` rewrite
