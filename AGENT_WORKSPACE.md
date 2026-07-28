---
git_backed: true
remote: github
branch_required: false
access: readwrite
inherit: true
owning_agent: shared
pre_edit_skill: git-config-tracking
notes: "TadMSTR/homelab-agent on GitHub — remote inherited from the ~/repos/personal/ root marker is correct. branch_required is overridden to false: 346 of 350 commits are direct-to-main, across every subdirectory, not just docs/. Ownership is shared rather than developer — writer owns docs/ per ADR-0003 (see docs/AGENT_WORKSPACE.md), while scripts/, docker/, pm2/ and manifests/ hold developer- and sysadmin-maintained mirror copies. inherit: true so subdirectories without their own marker fall through to this one."
---

# homelab-agent — forge

Public GitHub repo (`TadMSTR/homelab-agent`) serving as a generic reference for the forge
agent platform. This marker overrides the `~/repos/personal/` root marker, which declares
`branch_required: true, owning_agent: developer` for every child via `inherit: true`.

## Why `branch_required: false`

The repo's actual practice is direct-to-main by a wide margin — **346 of 350 commits**, with
only 4 merge commits in its entire history. That holds across every subdirectory, not just
`docs/`:

| Subdirectory | Commits | Practice |
|---|---|---|
| `docs/` | 212 | Direct-to-main doc commits, writer- and agent-authored |
| `pm2/` | 23 | Direct-to-main |
| `docker/` | 22 | Direct-to-main (1 recent PR) |
| `scripts/` | 20 | Direct-to-main (1 recent PR) |
| `mcp-servers/` | 16 | Direct-to-main |
| `claude-code/` | 13 | Direct-to-main |
| `manifests/` | 7 | Direct-to-main |

The inherited `branch_required: true` was surfaced during the writer's PR #291 merge: the
writer correctly followed it, then flagged that it doesn't fit the repo's doc-only workflow.
Setting it to `false` permits direct commits; it does not require them. Use a branch for
anything substantive — the four merges in history were all substantive changes.

## Why `owning_agent: shared`

The repo mixes two ownerships, so no single agent is accurate at the root:

- `docs/` — writer, per **ADR-0003** (component docs → `docs/components/`, runbooks →
  `docs/operations/`). Declared explicitly in `docs/AGENT_WORKSPACE.md`.
- `scripts/`, `docker/`, `pm2/`, `manifests/` — developer- and sysadmin-maintained mirror
  copies kept in sync with `host-forge-scripts` and `host-forge/stacks`. These fall through
  to this marker via `inherit: true`.

## Public-repo constraint

Per ADR-0003, content here must be **PII-free**: no forge-specific hostnames, IPs, or
internal paths. Use generic examples (`example.com`, `192.168.x.x`, `~/repos/personal/<repo>/`).
Phase-docs (forge-specific build records) belong in Gitea `host-forge/phases/`, not here.
