---
git_backed: true
remote: github
branch_required: false
access: readwrite
inherit: false
owning_agent: writer
pre_edit_skill: git-config-tracking
notes: "Writer-owned per ADR-0003 (agent-platform-agents/decisions/0003-writer-doc-queue-routes-to-homelab-agent.md), which routes component docs to docs/components/ and runbooks to docs/operations/. Overrides owning_agent: shared from the repo-root marker; branch_required: false matches it and the repo's actual direct-to-main doc workflow (212 doc commits, effectively all direct). Content must be PII-free — this is a public repo."
---

# homelab-agent/docs — writer-owned

## Why this marker exists

**ADR-0003** (accepted 2026-06-21) routes the writer agent's doc-queue output here:

- `component` → `docs/components/`
- `runbook` → `docs/operations/`
- `phase-doc` → **not here** — Gitea `host-forge/phases/`, because build records contain
  forge-specific detail unsuitable for a public repo

The repo-root marker declares `owning_agent: shared`, which is accurate for the repo as a
whole but not for this subtree. This override records the writer's ownership where it
actually applies, without claiming it over the developer/sysadmin mirror directories.

`branch_required: false` matches the repo root and the real workflow — 212 commits touch
`docs/`, effectively all direct to `main`. This was the specific mismatch surfaced during
the writer's PR #291 merge, where the writer followed the inherited `branch_required: true`
and then flagged that it doesn't fit a doc-only workflow.

## Public-repo constraint

Per ADR-0003, content here must be **PII-free**: no forge-specific hostnames, IPs, or
internal paths. Use generic examples (`example.com`, `192.168.x.x`, `~/repos/personal/<repo>/`)
when concrete values are needed.
