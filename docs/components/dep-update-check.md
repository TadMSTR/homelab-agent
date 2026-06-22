# dep-update-check

Weekly PM2 cron that checks host-global dependencies for available updates. Covers what Renovate (repo manifests) and Dockhand (Docker images) do not see: globally-installed npm packages, pip packages in managed venvs, the Claude Code CLI, and the system Node.js LTS version.

## Process

| Field | Value |
|-------|-------|
| PM2 name | `dep-update-check` |
| Schedule | `0 6 * * 4` (Thursdays 06:00) |
| Script | `~/scripts/check-dep-updates.sh` |
| Mode | PM2 cron fork (single run per window) |

## What it checks

| Package | Source | Notes |
|---------|--------|-------|
| `@tobilu/qmd` | npm global | Document search MCP CLI |
| `@cloudcli-ai/cloudcli` | npm global | CloudCLI developer shell |
| `pm2` | npm global | Major bump requires HITL — `pm2 update` re-execs the daemon |
| `@anthropic-ai/claude-code` | npm (claude installer) | Claude Code CLI |
| `memsearch` | pip `/opt/venvs/memsearch` | Memory search library |
| `nodejs` | system | Compared against current LTS from nodejs.org |

## Output

**JSON sidecar** — `~/.local/share/logs/dep-updates-latest.json`

Machine-readable; consumed by the sysadmin agent in Phase 1 of the update-cycle runbook.

```json
{
  "checked": "2026-06-19T06:00:00Z",
  "dependencies": [
    {
      "name": "@tobilu/qmd",
      "type": "npm",
      "source": "npm-global",
      "current": "1.2.3",
      "latest": "1.3.0",
      "updateAvailable": true,
      "majorBump": false
    }
  ]
}
```

**Log file** — `~/.local/share/logs/dep-updates-YYYY-MM-DD.log`

Human-readable run record. Cleaned up after 30 days.

**Matrix alert** — sent to the `sysadmin` room when any updates are available.

## Locking

A flock on `~/.local/state/dep-update.lock` prevents overlapping runs. If the cron fires while a previous check is still running, the new instance exits immediately.

## Operations

Check last run:
```bash
cat ~/.local/share/logs/dep-updates-latest.json | python3 -m json.tool
```

Run manually:
```bash
bash ~/scripts/check-dep-updates.sh
```

PM2 status:
```bash
pm2 show dep-update-check
```

## Dependencies

- `npm`, `node` — must be on PATH for the operator user
- `/opt/venvs/memsearch/bin/pip` — accessed via absolute path
- `send-matrix.sh` — Matrix notify; failure is non-fatal
- Internet access — queries npm registry and nodejs.org
