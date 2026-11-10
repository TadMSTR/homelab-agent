# githost-mcp

Unified local git + multi-provider remote MCP server (79 tools) with a per-agent HMAC-signed
JSONL audit trail as a first-class architectural feature. Covers local git operations via
gitpython (no subprocess), GitHub, Gitea, and GitLab APIs, Woodpecker CI, package registry
publishing, and release orchestration across all three providers simultaneously. It is the
one audited write path agents use for git: every agent gets its own process, its own
`AGENT_ID`, and its own read/write allowlist.

- **Version:** 0.21.0 (deployed 2026-11-08) — the last of four releases (0.18.0–0.21.0,
  all 2026-11-07/08) from parts 1–4 of a six-part hardening programme: CI diagnostics, per-call attribution and OTel-only telemetry, a
  machine-checkable grant model, and a correctness sweep. The Prometheus endpoint, Loki push
  and NATS publisher are gone (0.19.0). See [Version History](#version-history) for what
  changed since 0.5.0.
- **Repo:** `TadMSTR/githost-mcp` (public)
- **Transport:** `TRANSPORT=stdio` (default) or `http`. The reference deployment runs one
  long-lived HTTP process per agent under PM2, loopback-only and bearer-authed; one agent
  still uses a per-agent stdio launcher.
- **Agents:** registered per agent, one PM2 instance per agent named `githost-mcp-<agent>`.
  See [scoped-mcp integration](#scoped-mcp-integration) for the per-agent tool surface.

## Tools (79 total)

Higher-verb-count capabilities (PR/MR review, CI control, issues) are **method-dispatch**
tools — one tool takes a `method` argument and routes internally. Each `method` still writes
its own per-operation audit entry.

| Category | Tools |
|----------|-------|
| Local git (16) | `git_status`, `git_diff`, `git_log`, `git_show`, `git_branch`, `git_branch_delete_remote`, `git_checkout`, `git_add`, `git_commit`, `git_push`, `git_push_force_with_lease`, `git_pull`, `git_tag`, `git_remote` *(list/add/remove)*, `git_worktree` *(add/list/remove)*, `git_clone` |
| GitHub (21) | `github_repo_get`, `github_repo_create`, `github_create_release`, `github_get_release`, `github_list_releases`, `github_release_update`, `github_release_delete`, `github_workflow_list`, `github_workflow_status`, `github_actions`, `github_commit_checks`, `github_fork`, `github_pr_list`, `github_pr_comments`, `github_pr_create`, `github_pr_get`, `github_pr_update`, `github_pr_merge`, `github_pr_review`, `github_issue_read`, `github_issue_write` |
| Gitea (17) | `gitea_repo_get`, `gitea_repo_create`, `gitea_create_release`, `gitea_get_release`, `gitea_list_releases`, `gitea_release_update`, `gitea_release_delete`, `gitea_pr_list`, `gitea_pr_create`, `gitea_pr_get`, `gitea_pr_comment`, `gitea_pr_merge`, `gitea_pr_review`, `gitea_actions`, `gitea_commit_status`, `gitea_issue_read`, `gitea_issue_write` |
| GitLab (13) | `gitlab_create_release`, `gitlab_get_release`, `gitlab_list_releases`, `gitlab_release_update`, `gitlab_release_delete`, `gitlab_mr_list`, `gitlab_mr_create`, `gitlab_mr_get`, `gitlab_mr_merge`, `gitlab_mr_review`, `gitlab_pipeline`, `gitlab_issue_read`, `gitlab_issue_write` |
| Release orchestration (1) | `release` — git tag → GitHub/Gitea/GitLab release → PyPI → npm, with rollback on failure |
| Registry (2) | `pypi_publish`, `npm_publish` |
| Woodpecker CI (8) | `woodpecker_trigger`, `woodpecker_restart`, `woodpecker_list_pipelines`, `woodpecker_status`, `woodpecker_get_logs`, `woodpecker_pipeline_config`, `woodpecker_queue_info`, `woodpecker_pipeline_cancel` |
| Audit (1) | `audit_log_query` — query and verify the JSONL audit log; filters by `run_id`, `task_id` or `trace_id` since 0.19.0 |

The count matches the upstream README and the 0.21.0 deploy, where
`githost-mcp --list-tools --json` reported 79 tools, 14 of them `hitl: true` (see
[Grant model](#grant-model)).

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
- **CI diagnostics** (0.18.0) — an agent can find out why a run failed with githost-mcp
  tools alone. `woodpecker_get_logs`, `woodpecker_pipeline_config`, `gitea_actions
  get_job_log` and `github_actions get_job_log` share one bounded, scrubbed reader:
  `tail`/`head`/`range` modes, a literal-substring `grep` (never a regex) with context, at
  most 500 lines and about 64 KB per response, with paging fields. With no `step_name`,
  `woodpecker_get_logs` picks the first failed step and defaults to `tail` (before, it kept
  the *first* 500 lines of `clone`). Log text and the grep string never reach the audit
  trail. Treat log text as sensitive anyway: the scrubber removes githost-mcp's own tokens,
  URL userinfo and known credential shapes, not every secret a pipeline prints.
- **Woodpecker ids** (0.18.0) — `pipeline_id` is the per-repo pipeline **number** in every
  Woodpecker tool, input and output; the global id comes back as `internal_id` and no tool
  accepts it. `woodpecker_status` adds step states, exit codes, `errors[]` and a
  `stalled_hint`; `woodpecker_list_pipelines` filters server-side. Callers that read the
  old `id`/`number` keys must change.
- **`woodpecker_restart`** (0.18.0, write) — re-runs a pipeline with its original event, so
  a push-only failure reproduces (`woodpecker_trigger` makes a `manual` run). That includes
  tag, release, deployment and cron pipelines. Grant it as you grant `woodpecker_trigger`.
  `woodpecker_queue_info` (needs an admin Woodpecker token) lists running and pending items.
- **`gitea_commit_status` / `github_commit_checks`** (0.18.0) — "did CI pass on this sha".
  Woodpecker reports to Gitea as a commit status. Since 0.21.0 the Gitea read covers every
  page of contexts (up to 10 × 50) and takes the worst state; Gitea's own combined state
  covers one page, so a failure past it read as success.
- **Merge parameters** (0.21.0) — `github_pr_merge(commit_message=…)` sets the merge commit
  body (the audit records `custom_body: true|false`, never the text), so a squash no longer
  has to carry every branch commit message. `gitea_pr_merge(delete_branch_after_merge=…)`
  deletes the head branch once merged. `gitea_pr_merge`'s `message` was silently ignored
  before 0.21.0 (wrong field name) and now works.
- **`git_commit` on a merge** (0.21.0) — concluding a conflicted merge now records every
  parent and clears the merge state, in a plain clone and in a linked worktree. Before, it
  wrote a one-parent commit and left `MERGE_HEAD` behind. Commit signing with
  `GIT_SIGNING_KEY` also works again; before 0.21.0 every signed agent commit failed.

**New tools reach no agent until an allowlist names them** (0.20.0 deploy). Before, two
resident agents and the desktop-session manifests used `tool_denylist`, which fails open:
every new verb (0.18.0's `woodpecker_restart`, for example) was live for them the moment a
version loaded unless a denylist row landed first. All githost-mcp manifest blocks are now
allowlists, and a deploy-time gate refuses a grant that breaks the rules (see
[Grant model](#grant-model)). scoped-mcp still skips allowlist entries for tools the old
upstream did not serve, so a version that adds tools needs the proxies restarted after it
loads.

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
  "run_id": "<uuid>",
  "task_id": "<uuid>",
  "session_id": "<scoped-mcp session>",
  "trace_id": "<32 hex>",
  "effect": {"remote": "origin", "ref": "main", "old_sha": "<40 hex>", "new_sha": "<40 hex>",
             "forced": false, "lease": false, "flags": ["FAST_FORWARD"]},
  "hmac": "a3f8..."
}
```

- **`effect`** (0.19.0) — a successful write call records what it changed: SHAs, the
  resolved ref, PR/issue/review/comment/release/run/pipeline numbers, and counts. Never a
  commit message, body, file name or URL; strings are scrubbed, then bounded. A field that
  cannot be determined is `null` and listed in `effect_incomplete`, and the call still
  succeeds. Every tool is classified as an effect or a read tool, and a test fails on an
  unclassified one. Before 0.19.0, `git_push` with a defaulted branch audited only
  `branch: null`.
- **Correlation fields** (0.19.0) — `run_id`, `task_id`, `session_id` and `trace_id` are on
  every entry, rejections included, and `null` when absent. See
  [Per-call attribution](#per-call-attribution-forward_identity).

- Each entry is HMAC-SHA256 signed with `AUDIT_SIGNING_KEY`. `audit_log_query` verifies every
  returned entry and sets `tamper_detected: true` on any that fail; unsigned entries are
  never reported as verified. HMACs are per entry (not a chain), so a rotated entry verifies
  exactly as before the rename, and `audit_log_query` searches rotated backups too.
- The scheme is symmetric — it proves the file wasn't edited after write, not that agent
  identity is genuine. Identity proof is scoped-mcp's job.
- Every non-ok record carries a scrubbed `reason` (0.14.0), and enum rejections record the
  rejected argument and value, bounded to 64 characters (0.15.0).
- Credential fields are filtered before write — token values never appear in audit entries,
  logs, or error returns. Since 0.21.0 the scrubber also redacts by shape: `Authorization`
  values and vendor-prefixed tokens (`ghp_`, `glpat-`, `npm_`, `pypi-` and similar).
- `effect` and the correlation fields sit inside the HMAC'd entry, so altering either makes
  the entry verify as tampered. Entries are about 80 bytes longer than before 0.19.0, so the
  audit file reaches `AUDIT_LOG_MAX_BYTES` sooner.

### Per-call attribution (`forward_identity`)

Since 0.19.0 an audit entry can say which dispatcher run, task-queue task and scoped-mcp
session a call belonged to, and which trace it was part of.

- **What it is.** scoped-mcp (≥ 1.20.0) adds three headers to each proxied call:
  `X-Forge-Run-Id`, `X-Forge-Task-Id` and `X-Forge-Session-Id` (the broker's per-client
  session). githost-mcp validates them (run and task ids must be UUIDs; the session id
  `[A-Za-z0-9._:-]{1,128}`), writes them to the audit entry as `run_id`, `task_id` and
  `session_id`, and sets `forge.run_id`/`forge.task_id`/`forge.session_id` on the span. An
  invalid header is dropped and named in `correlation_invalid`, never recorded.
  githost-mcp's own MCP session id can't do this job: scoped-mcp opens a new HTTP connection
  per call.
- **How it's configured.** `forward_identity: true` on the githost-mcp `mcp_proxy` block of
  the agent manifest. It is HTTP-only and off by default; on a stdio entry it is ignored with
  one warning. `scoped-mcp validate` refuses static `headers` that name one of the three. The
  reference deployment sets it on all six resident agents' githost-mcp blocks and nowhere
  else. githost-mcp works the same with or without the headers.
- **What lands in the audit trail.** `run_id`, `task_id`, `session_id` and `trace_id` on
  every entry, `null` when absent. `trace_id` is the OTel trace of the `githost.<tool>` span,
  so an entry joins to its trace even for an interactive session with no run id. In the reference
  deployment, run and task ids exist only for sessions the task dispatcher launches in `auto`
  mode; a `semi-auto` task or an interactive start sets none.
  `audit_log_query` filters on `run_id`, `task_id` and `trace_id` (exact match), and still
  reads only the calling agent's own file.
- **Attribution, not authorization.** Any holder of the bearer token can send any value in
  these headers. Nothing in githost-mcp gates on them; they are checked for shape and
  recorded, nothing more.

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

**Roots are matched as written** (0.21.0). A root is expanded and normalised, never
resolved; only the requested path is resolved. A root that is itself a symlink is refused.

**The manifest allowlist is read from a deployed, root-owned copy**, not a git working tree,
so an agent cannot widen its own grant by editing a checkout.

**Pushes are pinned to a ref namespace** (0.20.0). `git_push`, `git_tag` and `release`
validate every branch, tag and remote name before anything is pushed. `git_push` pushes one
existing local branch to the same-named remote branch, never a tag or another ref; `git_tag`
and `release` push under `refs/tags/` only. Before this, an ungated `git_push` could reach
remote-ref effects the HITL-gated tools exist to control.

**Publish children get an allowlisted environment** (0.21.0). `python -m build`, `twine`
and `npm` run repository code, so they get a short list of variables (`PATH`, `HOME`, locale
and similar) plus the one credential each needs, not githost-mcp's own environment.
`pypi_publish`'s `dist_dir` must stay inside the repo; `npm_publish`'s `registry` must be a
credential-free `https://` URL. GitPython's own git children and repository hooks still
inherit the full environment, and build code still runs as githost-mcp's user.

**HITL is name-based.** Every scoped-mcp enforcement layer keys on the tool *name*, never on
arguments. That is why destructive operations (`git_branch_delete_remote`,
`git_push_force_with_lease`, the repo-create verbs) are separate tools rather than flags.

**Public identity on third-party repos.** Commits to repos you control carry the agent
identity and an `agent-id:` trailer; commits to any repo with a third-party remote use
`GIT_PUBLIC_NAME`/`GIT_PUBLIC_EMAIL` instead, resolved from the repo's remotes rather than a
caller flag, so internal agent names don't leak into public history. Since 0.21.0 a
**public** repo under an account you own gets the public identity too: an owned, non-fork
GitHub repo gets the agent identity only when GitHub says it is private, and an undetermined
answer resolves public. The audit entry records the acting agent either way.

**No subprocess git** for normal operations — gitpython only, which removes command
injection via crafted `repo_path` or branch values. (`git_clone` runs git directly, with
gitpython's unsafe-protocol and unsafe-option checks called explicitly, because
`Repo.clone_from()` has no working timeout.)

**Credential isolation.** Each provider uses its own env vars; a compromised GitHub token
does not expose Gitea or GitLab credentials.

**HTTP transport surface.** `TRANSPORT=http` refuses to start unless bound to loopback
(override: `GITHOST_MCP_ALLOW_NONLOOPBACK=1`) and unless `GITHOST_MCP_AUTH_TOKEN` is set and at
least 16 characters. There is no metrics port to protect: the Prometheus endpoint was removed
in 0.19.0.

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

Structured logging (structlog, JSON-L) is always on, to stderr and a rotating file. Since
0.19.0 stderr carries WARNING and above only, whatever `LOG_LEVEL` says; the file log keeps
`LOG_LEVEL`. Since 0.21.0 the HTTP server also starts with no FastMCP banner, no update
check and no uvicorn INFO lines, so PM2's `githost-mcp-<agent>-error.log` holds only what
needs reading.

OTel is the **only** telemetry export (`githost-mcp[otel]`; the `observability` extra keeps
its name and now means `otel`). The audit JSONL is the durable record.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `<appdata>/githost-mcp/logs/githost-mcp.log` | Application log |
| `AUDIT_LOG_FILE` | `<appdata>/githost-mcp/audit/githost.jsonl` | Audit trail; the directory is created `0700` (0.21.0) |
| `AUDIT_LOG_MAX_BYTES` / `AUDIT_LOG_BACKUP_COUNT` | 10 MB / 5 | Audit rotation (rename, `.1` newest) |
| `LOG_LEVEL` | `INFO` | File log level (stderr is WARNING+ regardless) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — (no export) | OTLP traces and metrics |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | Must match the endpoint's port: `:4317` with `grpc`, `:4318` with `http`. A mismatch fails silently, with no telemetry at all |
| `OTEL_SERVICE_NAME` | `githost-mcp` | Set per agent (`githost-mcp-<agent>`), or every agent collapses into one service |

What OTel carries:

- **Metrics:** `githost.tool.calls`, `githost.tool.denied`, `githost.tool.duration` and
  `githost.release.targets`. `githost.tool.denied` carries a `reason_class` from a closed
  vocabulary derived from the exception type (`not_in_allowed_roots`, `write_glob_denied`,
  `push_rejected`, `invalid_argument`, `missing_argument`, `protected_branch`, `not_owned`,
  `already_exists`, …); a rising `other` means agents are hitting a limit the vocabulary
  cannot name yet.
- **Traces:** since 0.19.0 the `githost.<tool>` span opens when the call starts and ends
  when its audit entry is written, so its duration is the call's (before, it was opened
  after the work and lasted microseconds). Child spans cover the git operations
  (`git.push`, `git.commit`, `git.clone`, …) and each provider HTTP request (`http.gitea`,
  `http.github`, `http.gitlab`, `http.woodpecker`). Span attributes are a fixed set — no
  URL, query, token, body or exception message. A call ending in `error:*` marks the span
  ERROR. Trace propagation from scoped-mcp is FastMCP's and was already working.

**Removed in 0.19.0:** the Prometheus endpoint, the Loki push and the NATS publisher, with
the `prometheus`, `loki` and `nats` extras. Nothing consumed them: the Loki/NATS emitter had
no caller and nothing scraped the metrics ports. `METRICS_PORT`, `LOKI_URL`, `LOKI_LABELS`,
`NATS_URL` and `NATS_SUBJECT_PREFIX` are now ignored; a set one logs
`config_ignored_removed_backend` once, by name, at startup.

## Deployment

**Install from the lock (0.17.0+):** `uv sync --frozen`, with `--extra observability` for
OTel export (since 0.19.0 that is the `otel` extra and nothing else). The lock is the
control; the floors in `pyproject.toml` are a second line for an install that re-resolves
into an existing venv.

**One process per agent, not one shared process.** Each agent gets its own OS process, own
`AGENT_ID`, own tokens, and own allowlist, so a compromised process can't see another
agent's credentials and `AGENT_ID` can't be spoofed via a request header. The repo's
`ecosystem.config.js` builds one PM2 app per agent from a single `AGENT_ID → {httpPort}`
map (`metricsPort` left it in 0.19.0). Since 0.21.0 it defines only the six live agents;
the decommissioned harlock and steward rows are gone.

```bash
pm2 start ecosystem.config.js --only githost-mcp-<agent>
pm2 save
```

A process first started from a pre-0.19.0 ecosystem file keeps `METRICS_PORT` in its stored
PM2 env across a plain restart. That is harmless — 0.19.0+ ignores it and logs one
`config_ignored_removed_backend` warning — and recreating the process from the current file
drops it.

**Grant gate before restart** (0.20.0+). The reference deploy runs
`githost-mcp --list-tools --json` from the freshly built venv and lints the deployed
manifests against it *before* restarting any process (see [Grant model](#grant-model)). A
refusal leaves the running processes on the old code, but the refused wheel stays installed
until rolled back.

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
invisible to callers until the proxy restarts. Add `forward_identity: true` to the block to
get per-call attribution (see
[Per-call attribution](#per-call-attribution-forward_identity)).

### Grant model

Since 0.20.0 githost-mcp states which of its tools are destructive enough to need a HITL
gate, and prints its tool surface so a deploy can check the manifests against it.

- **Every tool is classified.** Each tool is an effect tool or a read tool, and a test fails
  on an unclassified one. `HITL_TOOLS` is the 14 effect tools a manifest may grant only
  behind HITL approval: the three merges, `git_branch_delete_remote`,
  `git_push_force_with_lease`, the three `*_release_delete`, `woodpecker_pipeline_cancel`,
  `release`, `npm_publish`, `pypi_publish` and both `*_repo_create`. The remaining effect
  tools are pinned by a test too, so moving a verb in or out of the class is a reviewed
  change.
- **Ungated is not harmless.** `git_tag` push, the release create/update tools, the
  `github_actions` dispatch and cancel methods, `gitlab_pipeline` and the Woodpecker
  triggers are outside the HITL class but can publish or deploy in a repo wired to do so,
  and `git_push` can fast-forward a default branch, with server-side branch protection as
  the only control. Whether to gate them is an open decision (vikunja#1440).
- **`githost-mcp --list-tools [--json]`** prints every tool with its `kind` (`read` |
  `effect`) and `hitl` flag, then exits. It starts no server, needs no env var and writes no
  log, so it runs against a freshly built venv before anything restarts.
- **A deploy-time grant lint** in the reference deployment consumes that JSON. It refuses a
  manifest that grants a `hitl: true` tool without listing it under HITL approval, or that
  restricts githost-mcp with a denylist instead of an allowlist, and it names allowlist
  entries the server no longer serves. On the scoped-mcp side (1.21.0), a proxy with no
  `tool_allowlist` logs an `mcp_proxy_unfiltered` warning at startup.

Per-agent tool surface in the reference deployment (githost-mcp allowlist counts from the
deployed manifests, 2026-11-08):

| Agent | List type | Tool surface |
|-------|-----------|--------------|
| `developer` | allowlist (52) | Local git incl. `git_worktree`, `git_tag`, `git_clone`, `git_push_force_with_lease`, `git_branch_delete_remote`; `release`; GitHub/Gitea PR create/get/list/merge, `github_pr_update`, releases, workflows, `github_actions`; repo get/create; Woodpecker incl. `woodpecker_restart`, `woodpecker_pipeline_config`, `woodpecker_queue_info`; `gitea_commit_status`, `github_commit_checks`. **HITL:** all three providers' merge tools, `woodpecker_pipeline_cancel`, `git_branch_delete_remote`, `git_push_force_with_lease`, `release`, both `*_repo_create` |
| `sysadmin` | allowlist (44) | Similar to developer, minus most release CRUD and `github_actions`; has the same five 0.18.0 CI tools. Same HITL set as developer |
| `security` | allowlist (30) | Commit/push for its own reports, plus read verbs: PR/issue/release/workflow reads, `gitea_actions`/`github_actions`, the 0.18.0 CI reads, `github_issue_write`. No merge, tag, release, clone, or worktree |
| `research` | allowlist (48) | Converted from a denylist in the 0.20.0 deploy: the same effective set, minus the three `*_release_delete`, the three `*_release_update` and `github_fork`. No tag, release, registry publish, merge, PR/MR create, `woodpecker_restart`, `woodpecker_queue_info`, clone, worktree, force-push or repo create |
| `writer` | allowlist (38) | Commits docs directly to `main`. Converted from a denylist in the 0.20.0 deploy, minus the same seven verbs as research. No tag, checkout, release, registry publish, Woodpecker tool, PR/MR tool, clone, worktree, force-push or repo create. Writes are further limited to doc paths by `write_globs` |
| `fleet` | allowlist (19) | Local git without tag/worktree/force-push, Gitea/GitHub PR create/get/list, `gitea_pr_comment`, `github_issue_write`. No merge, tag, release, or remote-branch delete; write scope is limited by policy to per-host compose repos |
| `harlock` | — | **Decommissioned 2026-08-08** ([harlock.md](../agent/harlock.md)); its manifest was deleted in the 0.20.0 deploy. It had a denylist stdio launcher, never a PM2 instance. `steward` (below) is a separate, later agent, not a rename |
| `steward` | allowlist (8) | Read verbs plus `gitea_pr_create`/`gitea_pr_comment` — opens a PR carrying a config diff, never lands one. Parked: its manifest remains, but since 0.21.0 `ecosystem.config.js` defines no steward app |

Desktop-session manifests for developer, research, security, sysadmin and writer also carry
githost-mcp entries. Since the 0.18.0 deploy they are allowlists, so a new tool reaches no
desktop session until it is added there, and the 0.20.0 deploy trimmed them of the
destructive verbs (the merges, `git_branch_delete_remote`, the release deletes): a desktop
session has no HITL path, and the client's "Allow always" is not a gate.

## Version History

| Version | Date | Highlights |
|---------|------|-----------|
| 0.21.0 | 2026-11-08 | Correctness sweep, no tool-surface change (79 tools, 14 HITL-class): `github_pr_merge(commit_message)`, `gitea_pr_merge(delete_branch_after_merge)`; merge commits keep every parent; signed commits work again; Gitea combined status reads every page; credential-shape scrubbing; allowlisted publish-child environment; roots matched as written, symlinked roots refused; atomic `git_clone`; public owned repos get the public identity; quiet stderr at startup; `ecosystem.config.js` lists the six live agents |
| 0.20.0 | 2026-11-08 | Grant model: `HITL_TOOLS` (14) and pinned ungated set; `githost-mcp --list-tools [--json]` for a pre-restart grant gate; `git_push`/`git_tag`/`release` validate names and push with the ref namespace pinned. Tool surface unchanged (79) |
| 0.19.0 | 2026-11-08 | Attribution and telemetry: `effect` on every write call; `run_id`/`task_id`/`session_id`/`trace_id` on every entry (via scoped-mcp `forward_identity`); `audit_log_query` filters by them; `githost.<tool>` span covers the real work, with git and HTTP child spans; stderr WARNING+. **Removed** the Prometheus endpoint, Loki push, NATS publisher and their extras (githost-mcp#35); OTel only |
| 0.18.0 | 2026-11-07 | CI diagnostics: one bounded, scrubbed CI log reader; `woodpecker_restart`, `woodpecker_pipeline_config`, `woodpecker_queue_info`, `gitea_commit_status`, `github_commit_checks`, `github_actions` `list_jobs`/`get_job_log` — 74 → 79 tools; Woodpecker `pipeline_id` is the per-repo number everywhere (`internal_id` for the global id); validator anchoring hardened |
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
