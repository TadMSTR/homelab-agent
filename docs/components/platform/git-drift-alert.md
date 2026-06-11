# git-drift-alert

Scheduled job that detects uncommitted changes in tracked platform repos and sends Matrix
alerts. Re-alerts only when drift state changes — not on every scan.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `git-drift-alert` |
| Type | cron |
| Schedule | `*/30 * * * *` (every 30 min) |
| Script | `~/scripts/git-drift-alert.sh` |
| Port | — (no listener) |

## Monitored Repositories

| Path | Label |
|------|-------|
| `~/repos/gitea/agent-platform-agents` | agent-platform/agents |
| `~/.claude/skills` | agent-platform/skills |
| `~/repos/gitea/host-forge-scripts` | host-forge/scripts |
| `~/repos/gitea/host-forge-build-reports` | host-forge/build-reports |
| `~/repos/gitea/agent-platform` | agent-platform/kb |
| `~/repos/gitea/host-forge` | host-forge/docs |

## How It Works

1. Iterates each monitored repo and runs `git status --porcelain`
2. Hashes the status output (SHA-256) and compares against last known state in `~/.local/state/git-drift/`
3. If hash changed (new or different drift), sends a Matrix alert to `#agents` via `send-matrix.sh`
4. If hash matches previous scan, stays silent (no repeat alerts)
5. If repo is clean and was previously dirty, sends a "resolved" alert

## Dependencies

- `~/scripts/send-matrix.sh` — Matrix notification script (uses `~/.secrets/matrix-forge.env`)
- Git — for status checks on each repo

## Operations

```bash
pm2 logs git-drift-alert --lines 50    # last scan output
pm2 restart git-drift-alert             # trigger manual scan
ls ~/.local/state/git-drift/            # view per-repo state hashes
```

## Related Docs

- platform-health — other health monitoring
