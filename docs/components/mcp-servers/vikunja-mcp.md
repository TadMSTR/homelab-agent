# vikunja-mcp

vikunja-mcp is a FastMCP server wrapping the [Vikunja](https://vikunja.io) REST API — 75
tools spanning the full Vikunja resource surface: projects, project sharing, tasks,
assignees, relations/reminders, backlinks, ticket sweeps, kanban buckets/views, labels,
comments, filters, attachments, teams, and webhooks. It targets Vikunja's `/api/v2`, so it requires **Vikunja
2.4.0 or newer** (v1 is frozen upstream at 2.4.0 and removed at 4.0).

- **Package:** `vikunja-mcp` (`~/repos/personal/vikunja-mcp`), published as
  `ghcr.io/tadmstr/vikunja-mcp:v0.13.0` (deployed 2026-10-27; verified in `docker ps`
  2026-11-02)
- **Transport:** streamable-http — `127.0.0.1:8501`. **Container**, not PM2 — moved into the
  `~/docker/vikunja/` compose stack (alongside the `vikunja` app and `vikunja-db`) at v0.6.0. A
  `vikunja-mcp` PM2 entry still shows in `pm2 jlist` but is `stopped`, a dormant leftover
  (vikunja#468/#498, both still open), not the live service — verified live 2026-09-28
  (`docker ps` shows the container `Up`/`healthy`; PM2 shows `stopped`). See
  [vikunja.md](../apps/vikunja.md) for the full stack.
- **Vikunja URL:** `https://vikunja.example.com`
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

Runs as the `vikunja-mcp` container in `~/docker/vikunja/docker-compose.yml`
(`ghcr.io/tadmstr/vikunja-mcp:<tag>`), configured via `~/docker/vikunja/.env` — `VIKUNJA_URL`,
`VIKUNJA_PORT`, and the other vars below. **No token in the compose env** — see
[Why it's shaped this way](#why-its-shaped-this-way--token-passthrough) above.

## Configuration

| Env var | Purpose | Default |
|---------|---------|---------|
| `VIKUNJA_URL` | Base URL of the Vikunja instance (no `/api/v2`) | none — required; server fails closed with `ConfigError` at startup if unset. There is no hardcoded default and none is planned. |
| `VIKUNJA_HOST` | Bind address | `127.0.0.1` |
| `VIKUNJA_PORT` | Bind port | `8501` |
| `VIKUNJA_TRANSPORT` | `http` or `stdio` | `http` |
| `VIKUNJA_REQUEST_TIMEOUT` | Upstream timeout (seconds) | `30` |
| `VIKUNJA_INFLUXDB3_URL` / `_TOKEN` / `_DATABASE` | InfluxDB 3 metrics sink | off |
| `VIKUNJA_NATS_URL` / `_SUBJECT` | NATS metrics sink | off |
| `VIKUNJA_AUDIT_LOG` | Enable `contrib/audit_log.py` request/response audit logging | off (`0`) |
| `VIKUNJA_AUDIT_LOG_DIR` | Directory for audit log output when `VIKUNJA_AUDIT_LOG=1` | — |

No Vikunja token is ever written to the env file — that's the point of the passthrough
model. Per-agent tokens live in Vault at `secret/data/vikunja/agent-<role>`.

## Tools

75 tools spanning the full Vikunja resource surface — 71 as of v0.2.0, plus
`backlog_summary` (v0.7.0), `task_link_commit` (v0.8.0), and `tasks_export` and `task_close`
(v0.13.0). The 73-tool count was reverified with a `tools/list` call against the running
container 2026-09-28; the 75 is counted from the `@tool` registrations in the v0.13.0
source (2026-11-02). See the [repo
README](https://github.com/TadMSTR/vikunja-mcp#tools) for the full table.
Notable points:

- **Ticket sweeps (v0.13.0).** `tasks_export(project_id, include_done=true, since=None)`
  returns every task in a project as one compact row each, with no description. It pages
  to completion or raises, and `since` keeps tasks updated at or after a timestamp.
  `task_close(task_id, verdict, evidence, ...)` posts a `Closing: <VERDICT> — <evidence>`
  comment, adds the relation the verdict implies, and marks the task done, in one call.
- **Smaller replies (v0.13.0).** `task_get` takes `fields=[...]` and
  `include_comments=true`. `task_update`, `tasks_bulk_update`, `comment_create`,
  `task_label_add` and `task_relation_add` accept `return_mode="minimal"`. Defaults are
  unchanged.
- **Username, not user id (v0.12.0).** `project_user_update`, `project_user_remove` and
  `team_member_toggle_admin` take `username`; before v0.12.0 every call to them returned 404.

- **No `filter_list`** — Vikunja has no `GET /filters`; saved filters are exposed as
  pseudo-projects, so list them via `project_list` and fetch with `filter_get`.
- As of v0.9.0 (the `/api/v2` migration), Vikunja's REST idiom is **POST creates (201), PUT
  replaces, PATCH merges, DELETE returns 204** — the inverse of the old v1 idiom (PUT
  created, POST updated). One route doesn't follow the pattern — the team-admin toggle stays
  POST on both API versions. Tool names hide the verb either way.
- Project sharing permission ints: `0` = read, `1` = write, `2` = admin.
- **All list tools are paginated** (`page` / `per_page` args). Since v0.9.0, pagination comes
  back as a body envelope rather than response headers: a bare list when the result fits, or
  `{"items": [...], "pagination": {"truncated": true, "total_pages": N, "total": M, "count":
  K}}` when it doesn't. `total` is the size of the whole result set and `count` is the rows
  in this response — v1 could not report `total` at all.
- `webhook_create`'s SSRF guard is unchanged, but there is currently no valid
  `webhook_create` target on this deployment — the SECURITY.md/`docs/forge.md` webhook
  guidance was corrected in v0.4.0 to reflect that.

An extension-hook system (`hooks.py`) wraps every tool call with a pre/post handler chain
(`register_before` / `register_after`) — see `docs/extension-hooks.md` in the repo.

## Dependencies

- Vikunja app at `https://vikunja.example.com` ([vikunja.md](../apps/vikunja.md)) — same
  compose stack, `vikunja-db` as the shared datastore
- Vault (`secret/data/vikunja/agent-<role>`) for per-agent tokens

## Operations

```bash
docker ps --filter name=vikunja-mcp --format 'table {{.Names}}\t{{.Status}}'
docker logs vikunja-mcp --tail 50
cd ~/docker/vikunja && docker compose restart vikunja-mcp
curl -s http://127.0.0.1:8501/health
```

Restarting the whole stack (`docker compose down && docker compose up -d` from
`~/docker/vikunja/`) also restarts this container — see [vikunja.md](../apps/vikunja.md#operations)
for the full-stack procedure. There is no PM2 command for the live service; `pm2 show
vikunja-mcp` shows the stopped ghost entry, not this container.

## scoped-mcp Wiring

Registered in 6 agent manifests (`/etc/forge/manifests/*.yml`) as an `mcp_proxy` module
pointing at `http://127.0.0.1:8501/mcp`, each injecting `Authorization: Bearer
${VIKUNJA_TOKEN}` from its own Vault-sourced credential. Every manifest carries an explicit
`tool_allowlist`. A proxy freezes the tool list when it starts, so it has to be restarted
before a new tool or parameter shows up.

| Manifest | Access |
|----------|--------|
| `sysadmin-agent.yml` | Every tool except `tasks_export` (74 of 75). Five membership/admin tools need HITL approval on every call: `project_user_update`, `project_user_remove`, `team_member_toggle_admin`, `team_delete`, `team_member_remove` (added 2026-10-21 with v0.12.0) |
| `developer-agent.yml` | `whoami`, `project_list`, `project_get`, `task_list`, `task_search`, `task_get`, `task_create`, `task_update`, `label_list`, `label_get`, `label_create`, `task_label_add`, `task_label_remove`, `comment_list`, `comment_create`, `task_relation_add`, `task_relation_remove`, `task_assignee_list`, `attachment_list`, `attachment_upload`, `view_list`, `view_get`, `bucket_list`, `task_bucket_move`, `backlog_summary`, `task_link_commit`, `task_close` |
| `research-agent.yml` | `whoami`, `project_list`, `project_get`, `task_list`, `task_search`, `task_get`, `task_create`, `task_update`, `tasks_bulk_update`, `task_label_add`, `task_label_remove`, `task_relation_add`, `task_relation_remove`, `task_assignee_list`, `comment_list`, `comment_create`, `label_list`, `label_get`, `label_create`, `team_list`, `team_get`, `project_team_list`, `project_user_list`, `project_share_list`, `project_share_get`, `view_list`, `view_get`, `bucket_list`, `backlog_summary`, `task_link_commit`, `tasks_export`, `task_close` |
| `writer-agent.yml` | `whoami`, `project_list`, `project_get`, `task_list`, `task_search`, `task_get`, `task_create`, `task_update`, `task_label_add`, `task_label_remove`, `task_relation_add`, `label_list`, `comment_list`, `comment_create`, `backlog_summary`, `task_link_commit` |
| `security-agent.yml` | `whoami`, `project_list`, `project_get`, `task_list`, `task_search`, `task_get`, `label_list`, `label_get`, `comment_list`, `comment_create`, `team_list`, `team_get`, `project_team_list`, `project_user_list`, `project_share_list`, `project_share_get`, `view_list`, `view_get`, `bucket_list`, `task_assignee_list`, `backlog_summary` |
| `fleet-agent.yml` | `project_list`, `project_get`, `task_list`, `task_search`, `task_get`, `task_create`, `task_update`, `task_label_add`, `task_label_remove`, `task_relation_add`, `task_relation_remove`, `comment_list`, `comment_create` |

The v0.13.0 tools were granted 2026-10-27: `task_close` to sysadmin, developer and research,
and `tasks_export` to research only.

Project taxonomy (parent/child structure, label vocabulary, kanban buckets, sharing teams)
is defined in `host-forge/vikunja-structure.md` — **proposed**, not yet ratified.
