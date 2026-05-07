# Updater

**Last updated: 2026-05-07**

The updater is a nightly PM2 cron that coordinates software updates across Claude Code, Docker containers, the host OS, and Python/npm package globals. It uses soak windows to delay applying updates until they've stabilized, pre-fetches changelogs for manual-review items, runs parallel agent self-checks, and posts a structured summary to Matrix.

## Overview

The updater runs at **4:30 AM daily** via PM2. Its job is to keep Claude Code, stateless Docker containers, and package globals current while protecting stateful services from automatic updates. It covers eight phases in sequence:

| Phase | Script section | What happens |
|-------|---------------|-------------|
| Claude Code check | — | Compares installed vs available version; applies update if soak window has passed |
| Docker update check | Section B | Pulls new images for auto-update containers if soak window has passed; flags manual-update containers with digest diffs |
| apt check | Section C | Counts upgradable packages (security vs other); notifies but never applies |
| Matrix notification | Section D | Posts a structured summary of all update activity |
| Agent self-checks | Section E | Launches 7 headless Claude agents in parallel, each running their self-check skill |
| Update log | Section F | Writes a YAML log entry to the Gitea activity repo under `updates/YYYY-MM/` |
| Package globals | Section G | Soak-windowed pip3/npm update check and install for memsearch and qmd |
| Changelog research | Section H | Pre-fetches GitHub release notes for all pending manual-review items |

## Configuration

`~/scripts/updater-config.yml` controls all update behavior. Key sections:

```yaml
soak_windows:
  claude_code_hours: 24   # wait 24h before applying Claude Code updates
  docker_hours: 48        # wait 48h before pulling Docker images

docker:
  containers:
    auto_update:          # stateless — pulled and recreated automatically
      - crawl4ai
      - firecrawl-api
      - graphiti-mcp
      - searxng
      # ... (18 total)

    flag_manual:          # stateful — updates detected and reported, not applied
      - grafana
      - influxdb
      - neo4j
      - librechat
      # ... (20+ total)

    skip:                 # never touched
      - swag

  compose_services:       # maps each auto_update container to its compose file
    crawl4ai:
      compose_file: /home/ted/docker/crawl4ai/docker-compose.yml
      service: crawl4ai
```

### Soak Window Concept

When a new version is first detected, its timestamp is written to `~/.claude/scripts/updater-state.json`. On subsequent runs, the elapsed time since first detection is compared against `soak_windows.*_hours`. The update is only applied once the window has passed. This means:

- A nightly Claude Code update doesn't land until the next night at the earliest
- Docker image updates are held for two nights before auto-pull

Soak state survives reboots (it's a file, not memory). The `--force` flag bypasses windows for both Claude Code and Docker.

## CLI

```bash
~/scripts/updater run           # full update cycle (same as the PM2 cron)
~/scripts/updater --force       # bypass soak windows, apply all pending updates
~/scripts/updater --check-only  # detect updates, post Matrix summary, skip all applies
```

`--check-only` is useful for auditing what's pending without triggering anything. It runs all detection phases (A, B, C) and posts the Matrix summary, but skips the actual `docker compose up -d` and `claude update` calls.

## Docker Update Approach

Auto-update containers are updated via `docker compose up -d <service>` — not `docker restart`. This is intentional: `docker restart` only restarts the existing container process and does not apply a newly pulled image. The `compose_services` map in `updater-config.yml` provides the compose file and service name for each container so the correct command can be constructed.

Containers in `flag_manual` are checked for updates by comparing local image config digest against the remote manifest (using `docker manifest inspect`, no layer download). When an update is available, the container name is included in the Matrix summary's "flagged manual" line.

## Agent Self-Checks

After the Docker and apt phases, the updater launches 7 Claude agents in parallel (one per agent project), each running its own `self-check` skill. Each agent:
- Has a `self-check-<name>` skill in `~/repos/personal/claude-prime-directive/skills/`
- Writes a JSON result to a temp directory
- Times out after 4 minutes if unresponsive

Results are aggregated and included in both the Matrix notification (highlighted if any fail) and the Gitea update log.

## Matrix Notification

The updater posts a structured message to the `claudebox` Matrix room after each run:

```
🔄 Updater run — 2026-05-07 04:30 UTC
Claude Code: 1.2.3 (current)
Docker: 3 pulled, 1 pending soak, 2 flagged manual
apt: 4 packages pending (1 security) | reboot: no
packages: memsearch 0.4.1 (current) | qmd 0.3.0 → 0.3.1 (updated)
Self-checks launched: 7
```

## Update Log

Each run writes a YAML log entry to a Gitea repo under `updates/YYYY-MM/YYYY-MM-DD-HH.yml`. The entry includes Claude Code versions (before/after), Docker pull/flag lists, apt counts, and per-agent self-check results.

## PM2 Configuration

The cron is defined in `~/.claude/manifests/headless-updater.yml` (or `ecosystem.config.js`). PM2 runs `run-updater.sh`, which is a thin shim that sets up logging and calls `claude-update.sh`. All output goes to a timestamped log file at `~/logs/updater/`.

## Package Globals (Section G)

Section G handles soak-windowed updates for two package globals:

- **memsearch** (pip3) — after upgrade, the updater automatically re-applies three patches to the installed source files: `ollama.py` (base URL fix), `__init__.py` (embedding config), and `core.py` (NaN filter and compact resilience). These patches are wiped by every pip upgrade and must be re-applied immediately.
- **qmd** (`@tobilu/qmd`, npm) — qmd installs to a root-owned system path (`/usr/lib/node_modules/`) and cannot be upgraded by `ted` directly. The updater calls `sudo /usr/local/sbin/updater-qmd-install.sh`, a wrapper script granted NOPASSWD via `/etc/sudoers.d/updater-qmd`. After install, the wrapper re-applies the `QMD_HOST` patch that enables qmd to bind to non-localhost addresses (required for LibreChat's HTTP transport on port 8181). This patch is silently overwritten on every npm install — the wrapper is the canonical upgrade path; do not run `npm install -g @tobilu/qmd@latest` directly in automated contexts.

Both packages use the same 24-hour soak window as Claude Code. Soak state lives in `~/.claude/updater-state.json` under the `package_globals` key.

## Changelog Research (Section H)

Section H runs alongside Sections A–G at 4:30 AM. For every container in `flag_manual` and every package global with a pending update, it:

1. Looks up the GitHub releases API URL from the `changelog_urls` map in `updater-config.yml`
2. Fetches the latest release body (15s timeout, no layer download)
3. Scans for breaking-change keywords (`breaking change`, `migration required`, `incompatible`, `removed.*support`)
4. Writes a structured entry to `pending_manual` in `~/.claude/updater-state.json`

Each entry records: type, current/available version, first_seen timestamp, changelog summary (truncated to 500 chars), breaking flag, and any existing deferral state. Writes are atomic (`.tmp` + `os.replace`). Containers with no `changelog_urls` entry (e.g. internal forks with no public releases page) are silently skipped.

This pre-fetch runs before Ted wakes up so the `/manual-updates` skill can present changelogs instantly without live API calls. See [manual-updates-skill.md](manual-updates-skill.md).

## Related

- [`check-dep-updates.sh`](../scripts/check-dep-updates.sh) — the earlier, simpler predecessor (npm, pip, Docker, Claude Code check-only)
- `updater-state.json` — soak window state and pending manual queue (`~/.claude/updater-state.json`)
- Agent self-check skills in `claude-prime-directive/skills/self-check-*/`
- [manual-updates-skill.md](manual-updates-skill.md) — interactive workflow for applying flag_manual items
