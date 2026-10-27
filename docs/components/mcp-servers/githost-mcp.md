# githost-mcp

Unified local git + multi-provider remote MCP server (74 tools) with a per-agent HMAC-signed
JSONL audit trail as a first-class architectural feature. Covers local git operations via
gitpython (no subprocess), GitHub, Gitea, and GitLab APIs, Woodpecker CI, package registry
publishing, and release orchestration across all three providers simultaneously. It is the
one audited write path agents use for git: every agent gets its own process, its own
`AGENT_ID`, and its own read/write allowlist.

- **Version:** 0.17.0 (2026-10-26) — dependency-only release: `uv.lock` committed and
  installed from (`uv sync --frozen`), dependency floors raised, and CI audits the locked
  set rather than a fresh resolve. No tool or behaviour changes. See
  [Version History](#version-history) for what changed since 0.5.0.
- **Repo:** `TadMSTR/githost-mcp` (public)
- **Transport:** `TRANSPORT=stdio` (default) or `http`. The reference deployment runs one
  long-lived HTTP process per agent under PM2, loopback-only and bearer-authed; one agent
  still uses a per-agent stdio launcher.
- **Agents:** registered per agent, one PM2 instance per agent named `githost-mcp-<agent>`.
  See [scoped-mcp integration](#scoped-mcp-integration) for the per-agent tool surface.

## Tools (74 total)

Higher-verb-count capabilities (PR/MR review, CI control, issues) are **method-dispatch**
tools — one tool takes a `method` argument and routes internally. Each `method` still writes
its own per-operation audit entry.

| Category | Tools |
|----------|-------|
| Local git (16) | `git_status`, `git_diff`, `git_log`, `git_show`, `git_branch`, `git_branch_delete_remote`, `git_checkout`, `git_add`, `git_commit`, `git_push`, `git_push_force_with_lease`, `git_pull`, `git_tag`, `git_remote` *(list/add/remove)*, `git_worktree` *(add/list/remove)*, `git_clone` |
| GitHub (20) | `github_repo_get`, `github_repo_create`, `github_create_release`, `github_get_release`, `github_list_releases`, `github_release_update`, `github_release_delete`, `github_workflow_list`, `github_workflow_status`, `github_actions`, `github_fork`, `github_pr_list`, `github_pr_comments`, `github_pr_create`, `github_pr_get`, `github_pr_update`, `github_pr_merge`, `github_pr_review`, `github_issue_read`, `github_issue_write` |
| Gitea (16) | `gitea_repo_get`, `gitea_repo_create`, `gitea_create_release`, `gitea_get_release`, `gitea_list_releases`, `gitea_release_update`, `gitea_release_delete`, `gitea_pr_list`, `gitea_pr_create`, `gitea_pr_get`, `gitea_pr_comment`, `gitea_pr_merge`, `gitea_pr_review`, `gitea_actions`, `gitea_issue_read`, `gitea_issue_write` |
| GitLab (13) | `gitlab_create_release`, `gitlab_get_release`, `gitlab_list_releases`, `gitlab_release_update`, `gitlab_release_delete`, `gitlab_mr_list`, `gitlab_mr_create`, `gitlab_mr_get`, `gitlab_mr_merge`, `gitlab_mr_review`, `gitlab_pipeline`, `gitlab_issue_read`, `gitlab_issue_write` |
| Release orchestration (1) | `release` — git tag → GitHub/Gitea/GitLab release → PyPI → npm, with rollback on failure |
| Registry (2) | `pypi_publish`, `npm_publish` |
| Woodpecker CI (5) | `woodpecker_trigger`, `woodpecker_list_pipelines`, `woodpecker_get_logs`, `woodpecker_pipeline_cancel`, `woodpecker_status` |
| Audit (1) | `audit_log_query` — query and verify the JSONL audit log |

The count was verified against the `@mcp.tool` registrations in the source (74 unique
functions) and matches the upstream README.

### Tools worth knowing in detail

- **`git_worktree`** (0.15.0) — the one sanctioned way to get a scratch checkout. The
  destination is computed, never caller-supplied: `<worktree_root>/<repo>-<name>`, where
  `worktree_root` is `GITHOST_WORKTREE_ROOT`. The root is a location, not a grant — each
  destination is still checked against the agent's write roots. `remove` never forces, so a
  dirty worktree is refused. Agents that do scratch work (developer, sysadmin) now route it
  through this verb; before it existed they guessed `/tmp/…`-style paths and githost-mcp
  refused every one.
- **`git_push_force_with_lease`** (0.15.0) — updates a rebased branch with an explicit
  `--force-with-lease=refs/heads/<branch>:<expected_sha>`. `expected_sha` is a required full
  40-hex sha. `main`, `master`, and the remote's default branch are refused before any push.
  It is a separate tool (not a flag on `git_push`) so it can be HITL-gated by name.
- **`github_pr_update`** (0.15.0) — edits title/body/base, and `ready_for_review=True` takes a
  draft out of draft. It cannot close a PR.
- **`git_clone`** (0.16.0) — clones only repos whose owner you control: GitHub owners listed
  in `FORGE_OWNED_OWNERS`, or organizations on the configured Gitea (confirmed with
  `GET /orgs/{owner}`). There is no URL and no destination parameter; the path follows a
  fixed checkout convention and is validated against the write roots. An existing path or a
  symlink at the destination is refused, submodules are never cloned, and the clone is
  killed after 120 s. An agent whose grant is scoped by `write_globs` is refused outright,
  because a clone writes a whole tree.
- **`github_repo_create` / `gitea_repo_create`** (0.16.0) — create an **empty** repo.
  `visibility` (`public`/`private`) is required with no default, and the reported
  visibility is read back from the provider. Gitea creates in an organization only. There is
  deliberately no delete or visibility-change verb. **Gate both with HITL.**
- **`github_repo_get` / `gitea_repo_get`** (0.16.0) — read-only repo metadata (visibility,
  default branch, empty, archived, fork, parent, `delete_branch_on_merge`, URLs) for any
  repo; an absent or invisible repo returns `{"exists": false}`.
- **`git_branch(force=…)` and `git_branch_delete_remote`** (0.13.0) — `force` is needed to
  delete a squash-merged local branch; remote deletion is a separate, HITL-gateable tool and
  reports `already_absent` rather than a false "deleted".
- **`git_remote`** (0.11.0) — refuses (does not redact) a remote URL that embeds
  credentials, and refuses `ext::`/`fd::` remote helpers.

**New tools are live by default for denylist agents.** An agent restricted by
`tool_denylist` (rather than `tool_allowlist`) gets every new tool the moment a new version
loads. 0.15.0 and 0.16.0 both shipped with a deploy order: deny or HITL-gate the new verbs in
the manifests *before* installing, then restart allowlist agents' proxies a second time
(scoped-mcp skips allowlist entries for tools the old upstream did not serve).

## Audit Architecture

Every tool call writes a JSONL entry before returning:

```json
{
  "ts": "2026-05-27T09:14:23.000Z",
  "agent_id": "developer",
  "tool": "git_push",
  "provider": "local",
  "repo": "/home/<user>/repos/personal/example-mcp",
  "params": {"remote": "origin", "branch": "main"},
  "result": "ok",
  "duration_ms": 312,
  "hmac": "a3f8..."
}
```

- Each entry is HMAC-SHA256 signed with `AUDIT_SIGNING_KEY`. `audit_log_query` verifies every
  returned entry and sets `tamper_detected: true` on any that fail; unsigned entries are
  never reported as verified. HMACs are per entry (not a chain), so a rotated entry verifies
  exactly as before the rename, and `audit_log_query` searches rotated backups too.
- The scheme is symmetric — it proves the file wasn't edited after write, not that agent
  identity is genuine. Identity proof is scoped-mcp's job.
- Every non-ok record carries a scrubbed `reason` (0.14.0), and enum rejections record the
  rejected argument and value, bounded to 64 characters (0.15.0).
- Credential fields are filtered before write — token values never appear in audit entries,
  logs, or error returns.

## Security Model

**Separate read and write allowlists.** Read tools validate against `allowed_read_roots`,
write tools against `allowed_write_roots`. Resolution order:

1. `ALLOWED_REPO_ROOTS` env — applies to both lists (break-glass override)
2. `workspace-policy.yml` (`WORKSPACE_POLICY_PATH`) — the normal source in the reference
   deployment
3. The agent manifest's `git_backed: true` `workspace_access` entries (`AGENT_MANIFEST_PATH`)
4. Empty — fail closed, every path-taking tool is denied

**Write-glob scoping.** A policy grant can narrow writes to a glob subset with
`write_globs` / `write_globs_deny` (for example, a writer agent scoped to `docs/**`).
`git_add` checks the paths passed in and `git_commit` checks the full staged set; deny wins
over allow; traversal shapes like `docs/../src/x.py` are denied after normalization. A
rejection is audited as `denied:write_glob`.

**The manifest allowlist is read from a deployed, root-owned copy**, not a git working tree,
so an agent cannot widen its own grant by editing a checkout.

**HITL is name-based.** Every scoped-mcp enforcement layer keys on the tool *name*, never on
arguments. That is why destructive operations (`git_branch_delete_remote`,
`git_push_force_with_lease`, the repo-create verbs) are separate tools rather than flags.

**Public identity on third-party repos.** Commits to repos you control carry the agent
identity and an `agent-id:` trailer; commits to any repo with a third-party remote use
`GIT_PUBLIC_NAME`/`GIT_PUBLIC_EMAIL` instead, resolved from the repo's remotes rather than a
caller flag, so internal agent names don't leak into public history.

**No subprocess git** for normal operations — gitpython only, which removes command
injection via crafted `repo_path` or branch values. (`git_clone` runs git directly, with
gitpython's unsafe-protocol and unsafe-option checks called explicitly, because
`Repo.clone_from()` has no working timeout.)

**Credential isolation.** Each provider uses its own env vars; a compromised GitHub token
does not expose Gitea or GitLab credentials.

**HTTP transport surface.** `TRANSPORT=http` refuses to start unless bound to loopback
(override: `GITHOST_MCP_ALLOW_NONLOOPBACK=1`) and unless `GITHOST_MCP_AUTH_TOKEN` is set and at
least 16 characters. The Prometheus endpoint (`METRICS_PORT`) is hard-bound to `127.0.0.1`.

## Configuration

### Required

| Variable | Description |
|----------|-------------|
| `AGENT_ID` | Agent attribution — set per process |
| `AUDIT_SIGNING_KEY` | 32-byte hex key for HMAC audit entries |
| one allowlist source | `ALLOWED_REPO_ROOTS`, a `workspace-policy.yml` grant, or manifest `workspace_access` entries — with none, every path-taking tool is denied |

Generate an audit signing key: `python3 -c "import secrets; print(secrets.token_hex(32))"`

### Allowlist, identity, and worktrees (optional)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ALLOWED_REPO_ROOTS` | — | Comma-separated roots; overrides every other allowlist source |
| `WORKSPACE_POLICY_PATH` | `/etc/forge/workspace-policy.yml` | Policy file checked ahead of the manifest |
| `AGENT_MANIFEST_PATH` | `~/.claude/manifests/{AGENT_ID}-agent.yml` | Manifest fallback for the allowlist |
| `GIT_AGENT_NAME` / `GIT_AGENT_EMAIL` | `{AGENT_ID}-agent` / `{AGENT_ID}@forge` | Committer identity on repos you control |
| `GIT_PUBLIC_NAME` / `GIT_PUBLIC_EMAIL` | repo git config | Identity used on repos with a third-party remote |
| `FORGE_OWNED_OWNERS` | — | GitHub accounts/orgs you control; also `git_clone`'s owner allowlist |
| `GIT_SIGNING_KEY` | — | GPG key ID for commit signing |
| `GITHOST_WORKTREE_ROOT` | `~/repos/personal/_worktrees` | Where `git_worktree` creates worktrees; must sit inside the write roots |

### Transport

| Variable | Default | Purpose |
|----------|---------|---------|
| `TRANSPORT` | `stdio` | `stdio` or `http` |
| `HTTP_HOST` / `HTTP_PORT` | `127.0.0.1` / — | HTTP bind |
| `GITHOST_MCP_AUTH_TOKEN` | — | Bearer token, required for `http` (≥ 16 chars) |

### Provider credentials (all optional)

| Variable | Provider |
|----------|----------|
| `GITHUB_TOKEN`, `GITHUB_OWNER` | GitHub PAT (repo + workflow scope) |
| `GITEA_URL`, `GITEA_TOKEN`, `GITEA_OWNER` | Gitea instance (`write:repository`, `write:issue`) |
| `GITLAB_URL`, `GITLAB_TOKEN` | GitLab instance (`api` scope) |
| `WOODPECKER_URL`, `WOODPECKER_TOKEN` | Woodpecker CI |
| `PYPI_TOKEN`, `PYPI_TEST_TOKEN`, `NPM_TOKEN` | Package registries |

## Observability

Structured logging (structlog, JSON-L) is always on, to stderr and a rotating file.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `<appdata>/githost-mcp/logs/githost-mcp.log` | Application log |
| `AUDIT_LOG_FILE` | `<appdata>/githost-mcp/audit/githost.jsonl` | Audit trail |
| `AUDIT_LOG_MAX_BYTES` / `AUDIT_LOG_BACKUP_COUNT` | 10 MB / 5 | Audit rotation (rename, `.1` newest) |
| `LOG_LEVEL` | `INFO` | Log level |
| `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_PROTOCOL` / `OTEL_SERVICE_NAME` | — | OTLP tracing (`githost-mcp[otel]`); set the protocol explicitly to match the port, and a per-agent service name |
| `METRICS_PORT` | — | Prometheus endpoint, loopback-only (`githost-mcp[prometheus]`) |
| `LOKI_URL` | — | Loki shipping (`githost-mcp[loki]`) |
| `NATS_URL` | — | NATS publishing (`githost-mcp[nats]`) |

Metrics include `githost_tool_calls_total` and `githost_tool_denied_total{tool, agent_id,
reason_class}`. `reason_class` comes from a closed vocabulary derived from the exception
type (`not_in_allowed_roots`, `write_glob_denied`, `push_rejected`, `invalid_argument`,
`missing_argument`, `protected_branch`, `not_owned`, `already_exists`, …); a rising `other` means agents are hitting a limit the
vocabulary cannot name yet.

## Deployment

**Install from the lock (0.17.0+):** `uv sync --frozen` with the extras you need
(`--extra observability` for all of them). The lock is the control; the floors in
`pyproject.toml` are a second line for an install that re-resolves into an existing venv.

**One process per agent, not one shared process.** Each agent gets its own OS process, own
`AGENT_ID`, own tokens, and own allowlist, so a compromised process can't see another
agent's credentials and `AGENT_ID` can't be spoofed via a request header. The repo's
`ecosystem.config.js` builds one PM2 app per agent from a single `AGENT_ID → {httpPort,
metricsPort}` map:

```bash
pm2 start ecosystem.config.js --only githost-mcp-<agent>
pm2 save
```

**Restarting after a deploy.** Every PM2 process running from the shared venv is on the old
code until restarted. The reference deploy tooling derives the restart set from the live PM2
process table (every *online* process whose interpreter or script lives inside the venv)
rather than from a hand-written list or from `ecosystem.config.js`. The hand-written list
had drifted — one agent's instance ran stale code for weeks after deploys — and evaluating
the ecosystem file would also start apps that are deliberately stopped. Any process found
only by discovery is restarted and named in a warning so the list gets fixed.

```bash
pm2 list | grep githost-mcp        # the live instance set
pm2 logs githost-mcp-<agent> --lines 50
```

## scoped-mcp integration

Each agent's manifest points at that agent's own instance, with the bearer token as a
header:

```yaml
githost-mcp:
  type: mcp_proxy
  config:
    url: "http://127.0.0.1:<agent-port>/mcp/"
    headers:
      Authorization: "Bearer ${GITHOST_MCP_AUTH_TOKEN}"
    tool_allowlist: [...]      # or tool_denylist
```

`mcp_proxy` freezes the upstream tool list at proxy start, so a version that adds tools is
invisible to callers until the proxy restarts.

Per-agent tool surface in the reference deployment (verified against the agent manifests,
2026-10-26):

| Agent | List type | Tool surface |
|-------|-----------|--------------|
| `developer` | allowlist (47) | Local git incl. `git_worktree`, `git_tag`, `git_clone`, `git_push_force_with_lease`, `git_branch_delete_remote`; `release`; GitHub/Gitea PR create/get/list/merge, `github_pr_update`, releases, workflows, `github_actions`; repo get/create; Woodpecker. **HITL:** all three providers' merge tools, `woodpecker_pipeline_cancel`, `git_branch_delete_remote`, `git_push_force_with_lease`, `release`, both `*_repo_create` |
| `sysadmin` | allowlist (39) | Similar to developer, minus most release CRUD and `github_actions`. Same HITL set as developer |
| `security` | allowlist (27) | Commit/push for its own reports, plus read verbs: PR/issue/release/workflow reads, `gitea_actions`/`github_actions`, `github_issue_write`. No merge, tag, release, clone, or worktree |
| `research` | denylist (22 denied) | Everything except: tag, release, registry publish, all `*_create_release`, Woodpecker trigger/cancel, merges, PR/MR create, `github_pr_update`, `audit_log_query`, `git_branch_delete_remote`, `git_worktree`, `git_push_force_with_lease`, `git_clone`, both `*_repo_create` |
| `writer` | denylist (31 denied) | Commits docs directly to `main`. Denied: tag, checkout, release, registry publish, all `*_create_release`, every Woodpecker tool, **all PR/MR create/merge/comment/list tools**, `audit_log_query`, `git_branch_delete_remote`, `git_worktree`, `git_push_force_with_lease`, `github_pr_update`, `git_clone`, both `*_repo_create`. Writes are further limited to doc paths by `write_globs` |
| `fleet` | allowlist (19) | Local git without tag/worktree/force-push, Gitea/GitHub PR create/get/list, `gitea_pr_comment`, `github_issue_write`. No merge, tag, release, or remote-branch delete; write scope is limited by policy to per-host compose repos |
| `harlock` | denylist | stdio launcher, not a PM2 instance. Denies all local write tools, every PR create/comment/merge tool, all Woodpecker tools, `audit_log_query`, and the 0.15/0.16 verbs |
| `steward` | allowlist (8) | Read verbs plus `gitea_pr_create`/`gitea_pr_comment` — opens a PR carrying a config diff, never lands one. Its PM2 instance is currently stopped |

Desktop-session manifests for developer, research, and security also carry githost-mcp
entries; for those, the 0.16.0 repo-create verbs are denied outright (no HITL path in a
desktop session).

## Version History

| Version | Date | Highlights |
|---------|------|-----------|
| 0.17.0 | 2026-10-26 | `uv.lock` committed and installed from; raised dependency floors; CI audits the locked set, plus a gating `latest` job and a wheel-build job. No tool changes |
| 0.16.0 | 2026-10-25 | Repo bootstrap: `git_clone` (owned repos only), `github_repo_create`/`gitea_repo_create` (visibility required), `github_repo_get`/`gitea_repo_get` — 69 → 74 tools |
| 0.15.0 | 2026-10-24 | `git_worktree`, `git_push_force_with_lease`, `github_pr_update` — 66 → 69 tools; rejected values recorded in audit; `~` repo paths accepted |
| 0.14.0 | 2026-09-19 | `reason` on every non-ok audit record; `githost_tool_denied_total`; tool-call counter fixed; pre-flight guards now audited |
| 0.13.0 | 2026-08-30 | `git_branch_delete_remote`; `force` on `git_branch` delete; branch-name validation |
| 0.12.0 | 2026-08-25 | `woodpecker_get_logs` fixed (had never worked) |
| 0.11.0 | 2026-08-11 | `git_remote`, `github_fork`; public identity on third-party repos; read/write allowlist split + `workspace-policy.yml`; write-glob enforcement |
| 0.10.0 | 2026-08-01 | Push/empty-result reliability fixes; audit log rotation; manifest allowlist read from a deployed copy |
| 0.9.0 | 2026-07-27 | Credential scrubbing on every error return; `git_push` reports rejected pushes; metrics bind loopback |
| 0.7.0 | 2026-07-21 | Tier-1 parity: PR/MR review, CI control, release update/delete, issues via method-dispatch tools — 45 → 63 tools |
| 0.6.0 | 2026-07-16 | `TRANSPORT=http` with loopback + bearer requirements; per-agent PM2 apps |
| 0.5.0 | 2026-07-13 | GitHub/GitLab PR/MR create/merge parity; CI baseline |

Earlier releases (0.1.0–0.4.0) built the base tool set and the manifest allowlist fallback.
Full detail is in the repo's `CHANGELOG.md`.

## Related Docs

- [scoped-mcp.md](../agent/scoped-mcp.md) — the agent proxy that fronts githost-mcp
- Upstream README: `TadMSTR/githost-mcp` — full per-tool reference
