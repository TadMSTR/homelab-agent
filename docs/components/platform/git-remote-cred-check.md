# git-remote-cred-check

Scheduled job that scans tracked repos for plaintext credentials embedded in git remote URLs
(`https://<token>@host/...` or `https://user:<token>@host/...`) and alerts via Matrix. Companion
to [git-drift-alert.md](git-drift-alert.md), which checks for uncommitted changes — a separate
concern from remote URL contents.

- **Script:** `~/scripts/git-remote-cred-check.sh`
- **Schedule:** PM2 cron, daily (`0 4 * * *`)
- **Log:** `~/logs/git-remote-cred-check.log`
- **No listening port** — runs as a batch job
- **Origin:** git-credential-hygiene-2026-07 Phase 4

## How It Works

1. Finds every `.git` directory under `~/repos` (up to 4 levels deep)
2. Reads each repo's `origin` remote URL via `git remote get-url origin`
3. Flags any URL matching `^https://[^/]*[:@]` — an embedded token or `user:token@` pair
4. If any leaks are found, sends a Matrix alert to `#sysadmin` listing the affected repos
   (URL redacted after the `@`) and instructing rotation + re-pointing to SSH
5. If clean, logs and exits — no alert on a clean scan

## Configuration

| Setting | Value |
|---------|-------|
| Scan root | `~/repos` (maxdepth 4) |
| Leak pattern | `^https://[^/]*[:@]` |
| Log file | `~/logs/git-remote-cred-check.log` |
| Alert script | `~/scripts/send-matrix.sh` |
| Alert room | `#sysadmin` |

## Dependencies

- **Git** — `remote get-url` on each discovered repo
- **send-matrix.sh** — Matrix alerting on leak detection

## Operations

```bash
# Check last run
pm2 show git-remote-cred-check

# View log
tail -20 ~/logs/git-remote-cred-check.log

# Trigger manual scan
pm2 restart git-remote-cred-check

# Manually check a specific repo's remote
git -C ~/repos/personal/<repo> remote get-url origin
```

## Related Docs

- [git-drift-alert.md](git-drift-alert.md) — uncommitted change detection (separate concern, same naming convention)
