# githost-mcp

Unified local git + multi-provider remote MCP server (32 tools) with a per-agent HMAC-signed
JSONL audit trail as a first-class architectural feature. Covers local git operations via
gitpython (no subprocess), GitHub, Gitea, and GitLab APIs, plus release orchestration across
all three providers simultaneously.

- **Version:** 0.1.0 (deployed 2026-05-28, forge-q2-sync-deploy)
- **Repo:** `TadMSTR/githost-mcp` (public)
- **Transport:** stdio (per-agent launcher script)
- **Agents:** developer (primary), security (read tools)

## Tools (32 total)

| Category | Tools |
|----------|-------|
| Local git (11) | `git_status`, `git_diff`, `git_log`, `git_show`, `git_branch`, `git_checkout`, `git_add`, `git_commit`, `git_push`, `git_pull`, `git_tag` |
| GitHub (7) | `github_create_release`, `github_get_release`, `github_list_releases`, `github_workflow_list`, `github_workflow_status`, `github_pr_list`, `github_pr_comments` |
| Gitea (4) | `gitea_create_release`, `gitea_get_release`, `gitea_list_releases`, `gitea_pr_list` |
| GitLab (4) | `gitlab_create_release`, `gitlab_get_release`, `gitlab_list_releases`, `gitlab_mr_list` |
| Release orchestration (1) | `release` — coordinated multi-target release with rollback |
| Registry (2) | `pypi_publish`, `npm_publish` |
| Woodpecker CI (2) | `woodpecker_trigger`, `woodpecker_status` |
| Audit (1) | `audit_log_query` — query and verify JSONL audit log |

## Audit Architecture

Every tool call writes a JSONL entry before returning:

```json
{
  "ts": "2026-05-27T09:14:23.000Z",
  "agent_id": "dev",
  "tool": "git_push",
  "provider": "local",
  "repo": "/home/ted/repos/personal/signoz-mcp",
  "params": {"remote": "origin", "branch": "main"},
  "result": "ok",
  "duration_ms": 312,
  "hmac": "a3f8..."
}
```

Each entry is HMAC-SHA256 signed with `AUDIT_SIGNING_KEY`. `audit_log_query` verifies every
returned entry and sets `tamper_detected: true` on any that fail. This is symmetric (same
key signs and verifies) — it proves the file wasn't edited after write, not that agent
identity is genuine. Agent identity proof is scoped-mcp's responsibility.

Credential fields are filtered before write — token values never appear in JSONL entries.

## Security Model

**Repo path allowlist:** Write tools (`git_add`, `git_commit`, `git_push`, `git_tag`,
`git_checkout`, `git_branch create/delete`, `git_pull`, `release`, `pypi_publish`,
`npm_publish`) validate `repo_path` against `ALLOWED_REPO_ROOTS` before execution.
When `ALLOWED_REPO_ROOTS` is not set, write operations are disabled — fail-closed, not open.

**No subprocess git:** All local operations use gitpython (Python library), not subprocess.
This eliminates command injection via crafted `repo_path` or `branch` values.

**Credential isolation:** Each provider uses its own env vars. A compromised GitHub token
does not expose Gitea or GitLab credentials. Token values are never returned in tool output,
included in JSONL audit entries, or surfaced in exception messages.

## Configuration

### Required

| Variable | Description |
|----------|-------------|
| `AGENT_ID` | Agent attribution — set per launcher |
| `AUDIT_SIGNING_KEY` | 32-byte hex key for HMAC audit entries |
| `ALLOWED_REPO_ROOTS` | Comma-separated write allowlist — omitting disables all write tools |

Generate an audit signing key: `python3 -c "import secrets; print(secrets.token_hex(32))"`

### Provider Credentials (all optional)

| Variable | Provider |
|----------|----------|
| `GITHUB_TOKEN`, `GITHUB_OWNER` | GitHub PAT (repo scope) |
| `GITEA_URL`, `GITEA_TOKEN`, `GITEA_OWNER` | Gitea instance |
| `GITLAB_URL`, `GITLAB_TOKEN` | GitLab instance |
| `PYPI_TOKEN` | PyPI API token |
| `NPM_TOKEN` | npm automation token |

### Woodpecker CI (optional)

| Variable | Description |
|----------|-------------|
| `WOODPECKER_URL` | Woodpecker server URL |
| `WOODPECKER_TOKEN` | Woodpecker API token |

## Observability

Structured logging (structlog, JSON-L) is always on. Logs go to **stderr and a file simultaneously**.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/githost-mcp/logs/githost-mcp.log` | Log file path |
| `AUDIT_LOG_FILE` | `/opt/appdata/githost-mcp/audit/githost.jsonl` | Audit trail path |
| `LOG_LEVEL` | `INFO` | Structured log level |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | OTEL tracing (`pip install githost-mcp[otel]`) |
| `LOKI_URL` | — | Loki log shipping (`pip install githost-mcp[loki]`) |
| `METRICS_PORT` | — | Prometheus scrape endpoint (`pip install githost-mcp[prometheus]`) |
| `NATS_URL` | — | NATS publishing (`pip install githost-mcp[nats]`) |

Install all observability extras: `pip install "githost-mcp[observability]"`

**Forge status:** Structured logging and file logging are active. OTEL, Loki, NATS, and Prometheus extras are not installed on forge — only the base package is deployed. Configure by reinstalling with the relevant extras and setting the corresponding env vars.

## Launcher Pattern (forge)

Uses a Python launcher (not bash) — forge.env contains credentials with special characters
that bash `source` misinterprets. Single shared launcher for both developer and sysadmin:

```python
#!/usr/bin/env python3
# ~/scripts/run-githost-mcp.sh
import os

env = os.environ.copy()

# Load GitHub/Gitea tokens from forge.env
with open(os.path.expanduser("~/.secrets/forge.env")) as f:
    for line in f:
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            if k.strip() in ("GITHUB_TOKEN", "GITEA_TOKEN", "GITLAB_TOKEN"):
                env[k.strip()] = v.strip()

# Load githost-mcp config (ALLOWED_REPO_ROOTS, AUDIT_SIGNING_KEY, log paths)
with open(os.path.expanduser("~/.secrets/githost-mcp.env")) as f:
    for line in f:
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip()

python = "/opt/venvs/githost-mcp/bin/python3"
os.execve(python, [python, "-m", "githost_mcp.server"], env)
```

**Paths:**
- Venv: `/opt/venvs/githost-mcp/`
- Launcher: `~/scripts/run-githost-mcp.sh` (chmod +x)
- Secrets: `~/.secrets/githost-mcp.env` (chmod 600)
- Appdata: `/opt/appdata/githost-mcp/{logs,audit}/` (chmod 750)

`AGENT_ID` is injected per-agent via the manifest `env:` block (not the launcher), so the
same launcher script serves both developer and sysadmin agents.

## scoped-mcp Registration

Registered in developer and sysadmin manifests (`~/.claude/manifests/<agent>-agent.yml`):

```yaml
githost-mcp:
  type: mcp_proxy
  config:
    command: /home/ted/scripts/run-githost-mcp.sh
    env:
      AGENT_ID: developer   # or: sysadmin
```

`AGENT_ID` in the manifest `env:` block overrides any `AGENT_ID` in the process environment,
giving per-agent attribution in audit log entries without needing per-agent launchers.

## Security

From audit 2026-05-27 (4 findings, all resolved in commit `2edef93`):

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | `pypi_publish` and `npm_publish` bypassed `ALLOWED_REPO_ROOTS` — any path accepted | `validate_write_path()` added to both registry tools |
| L1 | Low | `git_pull` bypassed `ALLOWED_REPO_ROOTS` — inconsistent with all other write tools | `validate_write_path()` added to `git_pull` |
| L2 | Low | Dead import `_create_release_direct` in `release.py` caused GitHub step to always fail | Dead import removed; GitHub release path now functional |
| L3 | Low | `_rollback()` ignored `created`/`urls` — provider releases not cleaned up on failure | Rollback rewrites to use `created` list; GitHub/GitLab releases deleted on rollback |

35/35 tests pass post-remediation.

## Related Docs

- [scoped-mcp-forge.md](scoped-mcp-forge.md) — agent proxy that will load githost-mcp
- [forge-agent-setup.md](../../phases/forge-agent-setup.md) — agent framework context
