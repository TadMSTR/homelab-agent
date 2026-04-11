# Config Version Control

Three directories on claudebox contain the bulk of operational configuration and automation: `~/docker/` holds all Compose stacks, `/opt/appdata/` holds the runtime config files for running containers (YAML, TOML, JSON, INI), and `~/scripts/` holds the utility and maintenance scripts that run as PM2 jobs. Claude edits files in all three directories directly — which means changes needed a version history. A skill enforces pre/post-edit commits whenever Claude touches a tracked file, and a nightly snapshot catches anything that slipped through.

This isn't a substitute for backups. The docker-stack-backup job and Backrest both cover these paths. Version control adds something different: a timestamped audit trail of *what changed* and *why*, with the ability to diff or roll back individual files without restoring a full snapshot.

## Two Backends

Not everything tracked in git goes to the same place. Infrastructure state — compose files, appdata configs, maintenance scripts — goes to a self-hosted Gitea instance running on atlas. Code and projects meant to be shared or reused go to GitHub.

Gitea is appropriate for infra state: it's private, it's on the LAN, and it doesn't require an internet connection. These repos change frequently, may contain environment-specific context, and have no value outside this particular build. Keeping them off GitHub also avoids accidentally publishing configs that weren't fully sanitized.

GitHub is appropriate for code and documentation that has value beyond this machine — the context repo (skills, project instructions, infrastructure docs), public reference implementations like this one, and any MCP servers or tools worth releasing. If claudebox is rebuilt from scratch, these repos need to be clonable from somewhere reliable.

The split isn't mandatory. Running everything on GitHub or everything on a self-hosted Gitea both work fine. The distinction just reflects how the two categories of content are actually used.

Gitea runs on atlas as a single-container Docker stack with a SQLite backend — simple enough for a homelab and plenty sufficient for a few repos with light commit frequency.

## What's Tracked

| Local Path | Remote | Contents |
|------------|--------|----------|
| `~/docker/` | Gitea: `claudebox-docker` | All Docker Compose stacks and associated files |
| `/opt/appdata/` | Gitea: `claudebox-appdata` | Container config files by service |
| `~/scripts/` | Gitea: `claudebox-scripts` | Utility and maintenance scripts |
| `~/repos/personal/YOUR_CONTEXT_REPO` | GitHub: `your-context-repo` | Skills, project instructions, infrastructure docs |
| `~/repos/personal/homelab-agent` | GitHub: `homelab-agent` | Public reference repo (this repo) |

The context repo is handled differently from the config directories — it lives in a personal repos directory, is already a git repo tracking its own content, and pushes to GitHub rather than Gitea. The nightly snapshot covers it the same way: commit any changes, push. This catches edits made by Claude agents to skills or project instruction files that weren't committed inline.

## Skills and Project Instructions

Claude Code loads skills from `~/.claude/skills/<name>/SKILL.md` and project instructions from `~/.claude/projects/<name>/CLAUDE.md`. Both live in `~/.claude/` which is outside the version-controlled config directories — so they need their own approach.

The pattern is symlinks from the context repo. The actual files live in the context repo; `~/.claude/` holds symlinks pointing at them:

```bash
# Skills — symlink the whole skill directory
~/.claude/skills/docker-stack-setup -> ~/repos/personal/YOUR_CONTEXT_REPO/skills/docker-stack-setup/

# Project instructions — symlink the file (the containing directory has session data)
~/.claude/projects/homelab-ops/CLAUDE.md -> ~/repos/personal/YOUR_CONTEXT_REPO/claude-projects/homelab-ops/CLAUDE.md
```

Context repo structure for Claude Code content:

```
YOUR_CONTEXT_REPO/
├── skills/
│   ├── docker-stack-setup/
│   │   └── SKILL.md
│   └── security-audit/
│       └── SKILL.md
└── claude-projects/
    ├── homelab-ops/
    │   └── CLAUDE.md
    └── dev/
        └── CLAUDE.md
```

This means edits to skills or project instructions — whether made by Claude agents or directly in a text editor — are immediately reflected in `~/.claude/` and are tracked in git without any copy step. The nightly snapshot picks up any uncommitted changes. Inline commits happen whenever Claude edits a skill or instruction file as part of a task.

## .gitignore Strategy

The `/opt/appdata/` repo uses an inverted ignore pattern: ignore everything by default, then explicitly allow config file extensions. This keeps secrets and runtime state out of git without having to enumerate every file to exclude.

```gitignore
# Ignore everything
*
!*/
!*.yaml
!*.yml
!*.toml
!*.json
!*.ini

# Explicitly exclude secrets and runtime-generated files
authelia/users_database.yml
**/private_key.json
**/violations.json
swag/dns-conf/
swag/etc/
swag/keys/
swag/log/
swag/fail2ban/
swag/www/
```

The `~/docker/` repo excludes `.env` files (which contain secrets) and common runtime artifacts.

## Nightly Snapshot

A cron job runs at 2:55 AM daily, just before the 3 AM Backrest backup:

```bash
# ~/scripts/git-snapshot.sh
# Commits any uncommitted changes in both repos with message "nightly snapshot YYYY-MM-DD"
# Pushes to Gitea. Skips commit if there are no changes.
```

This catches any manual edits Ted makes directly — changes that weren't made through Claude and therefore didn't go through the pre/post-edit commit workflow. The snapshot runs before Backrest so the git history is consistent with what gets snapshotted on NFS.

## Claude Edit Workflow

A `git-config-tracking` skill enforces the commit discipline. Whenever Claude edits a file in `~/docker/`, `/opt/appdata/`, or `~/scripts/`, it follows this sequence:

1. **Pre-edit commit** — captures the current state before the change
2. **Make the edit**
3. **Post-edit commit** — captures the result with a descriptive message
4. **Push** to Gitea

This produces a clean two-commit history for every Claude-driven change: what it was before, what it is now, and why it changed. Both commits push immediately rather than waiting for the nightly snapshot.

## Permissions Note

Most files in `/opt/appdata/` are owned by container UIDs (e.g., `root`, `nobody`, service-specific users). Git operations — add, commit, push — work fine as `ted` because git only reads file content, not ownership. Write operations are a different story: if Claude needs to edit a file owned by a non-`ted` user, it may need `sudo chown ted:ted <file>` first. This is the most common friction point when editing container configs directly.

## Integration with Backups

Version control and backups cover the same directories but serve different purposes:

- **Backrest** (2 AM daily) snapshots `$HOME` which includes `~/docker/` and `~/scripts/`. Full restic snapshot, 90-day retention, recoverable as a point-in-time filesystem state.
- **docker-stack-backup** (1 AM daily) archives compose files + appdata into tarballs on NFS.
- **Git + Gitea** provides per-file change history with commit messages, diffing, and the ability to roll back individual files without a full restore.

For "what did this file look like three weeks ago?" git is faster. For "restore the whole stack from before that bad upgrade," Backrest or docker-stack-backup is the right tool.

## Standalone Value

Gitea + the snapshot script works with any Linux host where you want auditable change tracking for config directories. The inverted ignore pattern in `/opt/appdata/` is particularly useful for appdata directories that mix secrets, runtime state, and actual config — you get only the config files in git without having to audit every new service's directory structure manually.

## Related Docs

- [Backups](backups.md) — Full backup coverage for both directories
- [scripts/git-snapshot.sh](../../scripts/) — Nightly snapshot implementation
