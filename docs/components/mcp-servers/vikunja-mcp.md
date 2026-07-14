# vikunja-mcp

vikunja-mcp is a FastMCP server wrapping the [Vikunja](https://vikunja.io) REST API — 71
tools covering projects, project sharing, tasks, assignees, relations/reminders, kanban
buckets/views, labels, comments, filters, attachments, teams, and webhooks.

- **Package:** `vikunja-mcp` (`~/repos/personal/vikunja-mcp`, installed into
  `/opt/venvs/vikunja-mcp/`)
- **Transport:** streamable-http — `127.0.0.1:8501` (PM2, `/opt/appdata/vikunja-mcp/run.sh`)
- **Vikunja URL:** `https://vikunja.helmforge.me`
- **Auth:** stateless bearer-token passthrough (see below) — no credentials stored here
- **GitHub:** `TadMSTR/vikunja-mcp`

## Why it's shaped this way — token passthrough

The server holds **no** Vikunja credentials. Each agent has its own Vikunja account and API
token; vikunja-mcp reads the caller's bearer token off the incoming request and forwards it
to Vikunja unchanged. The token is injected upstream by each agent's own scoped-mcp instance
(pulled from Vault via the manifest's `credentials` block). A request with no `Authorization`
header is rejected fail-closed (`AuthError`) — there is no ambient fallback.

This means every call reaches Vikunja *as the agent that made it* (real per-agent
attribution in Vikunja's audit trail), and a compromise of this process only exposes one
in-flight request's token, never the full credential set.

## Launch

`ecosystem.config.js` points at `/opt/appdata/vikunja-mcp/run.sh`:

```bash
#!/bin/bash
set -euo pipefail
set -a
source /opt/appdata/vikunja-mcp/env   # VIKUNJA_URL, VIKUNJA_PORT — NO token here
set +a
exec /opt/venvs/vikunja-mcp/bin/vikunja-mcp
```

## Configuration

| Env var | Purpose | Default |
|---------|---------|---------|
| `VIKUNJA_URL` | Base URL of the Vikunja instance (no `/api/v1`) | `https://vikunja.helmforge.me` |
| `VIKUNJA_HOST` | Bind address | `127.0.0.1` |
| `VIKUNJA_PORT` | Bind port | `8501` |
| `VIKUNJA_TRANSPORT` | `http` or `stdio` | `http` |
| `VIKUNJA_REQUEST_TIMEOUT` | Upstream timeout (seconds) | `30` |
| `VIKUNJA_INFLUXDB3_URL` / `_TOKEN` / `_DATABASE` | InfluxDB 3 metrics sink | off |
| `VIKUNJA_NATS_URL` / `_SUBJECT` | NATS metrics sink | off |

No Vikunja token is ever written to the env file — that's the point of the passthrough
model. Per-agent tokens live in Vault at `secret/data/vikunja/agent-<role>`.

## Tools

71 tools spanning the full Vikunja resource surface (v0.2.0). See the
[repo README](https://github.com/TadMSTR/vikunja-mcp#tools) for the full table. Notable
points:

- **No `filter_list`** — Vikunja has no `GET /filters`; saved filters are exposed as
  pseudo-projects, so list them via `project_list` and fetch with `filter_get`.
- Vikunja's REST idiom is **PUT creates, POST updates** — tool names hide this.
- Project sharing permission ints: `0` = read, `1` = write, `2` = admin.

An extension-hook system (`hooks.py`) wraps every tool call with a pre/post handler chain
(`register_before` / `register_after`) — see `docs/extension-hooks.md` in the repo.

## Dependencies

- Vikunja app at `https://vikunja.helmforge.me` ([vikunja.md](../apps/vikunja.md))
- `/opt/venvs/vikunja-mcp/` Python venv
- Vault (`secret/data/vikunja/agent-<role>`) for per-agent tokens

## Operations

```bash
pm2 show vikunja-mcp
pm2 logs vikunja-mcp --lines 50
pm2 restart vikunja-mcp
curl -s http://127.0.0.1:8501/health
```

## scoped-mcp Wiring

Registered in all 5 agent manifests (`~/.claude/manifests/*.yml`) as an `mcp_proxy` module
pointing at `http://127.0.0.1:8501/mcp`, each injecting `Authorization: Bearer
${VIKUNJA_TOKEN}` from its own Vault-sourced credential.

| Manifest | Access |
|----------|--------|
| `sysadmin-agent.yml` | Full access (no allowlist) |
| `developer-agent.yml` | `project_list`, `project_get`, `project_create`, `task_list`, `task_search`, `task_get`, `task_create`, `task_update`, `label_list`, `label_create`, `task_label_add`, `comment_list`, `comment_create`, `whoami` |
| `research-agent.yml` | `project_list`, `task_list`, `task_search`, `task_get`, `task_create`, `whoami` |
| `writer-agent.yml` | `project_list`, `task_list`, `task_get`, `task_create`, `task_update`, `comment_create`, `whoami` |
| `security-agent.yml` | `project_list`, `task_list`, `task_search`, `task_get`, `whoami` |

Project taxonomy (parent/child structure, label vocabulary, kanban buckets, sharing teams)
is defined in `host-forge/vikunja-structure.md` — **proposed**, not yet ratified.
