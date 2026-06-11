# plane-mcp

plane-mcp is a FastMCP server wrapping the Plane project management API, giving forge
agents structured access to Plane — work items, projects, epics, cycles, modules, and
more — over an authenticated HTTP endpoint on localhost.

- **Package:** `plane-mcp` (installed from PyPI into `~/venvs/plane-mcp/`)
- **Transport:** streamable-http — `127.0.0.1:8495` (PM2, `run-plane-mcp.sh`)
- **Plane URL:** `http://127.0.0.1:3007` (Plane self-hosted on forge)
- **Auth:** Bearer token + `x-workspace-slug` header; validated by `PlaneTokenValidator` middleware against Plane's `/api/v1/users/me/` before FastMCP processes the request
- **Lockfile:** `~/repos/gitea/host-forge-scripts/venv-pins/plane-mcp.lock`

## Launch

PM2 process launched via `~/repos/gitea/host-forge-scripts/scripts/run-plane-mcp.sh`:

```bash
source ~/.secrets/plane.env
export PLANE_BASE_URL="http://127.0.0.1:3007"
export PLANE_API_KEY="${PLANE_TOKEN_RESEARCH}"
export PLANE_WORKSPACE_SLUG="${PLANE_WORKSPACE}"
exec /home/ted/scripts/run-plane-mcp.py
```

`run-plane-mcp.py` starts a `uvicorn` server on `127.0.0.1:8495` using the
`PlaneHeaderAuthProvider` + `PlaneTokenValidator` middleware stack.

## Configuration

| Env var | Source | Purpose |
|---------|--------|---------|
| `PLANE_BASE_URL` | Set in launcher | Plane API base URL (`http://127.0.0.1:3007`) |
| `PLANE_API_KEY` | `~/.secrets/plane.env` (`PLANE_TOKEN_RESEARCH`) | Default API key for token validation |
| `PLANE_WORKSPACE_SLUG` | `~/.secrets/plane.env` (`PLANE_WORKSPACE`) | Workspace identifier |

Per-agent tokens are injected at request time via the `Authorization: Bearer ${PLANE_TOKEN}`
header in each scoped-mcp manifest. The `PlaneTokenValidator` middleware validates each
inbound token against the live Plane API before forwarding the request.

## Tools

The full tool surface is large. Tools are grouped by resource type:

| Category | Tools |
|----------|-------|
| **Projects** | `list_projects`, `create_project`, `retrieve_project`, `update_project`, `delete_project`, `get_project_worklog_summary`, `get_project_members`, `get_project_features`, `update_project_features` |
| **Work Items** | `list_work_items`, `create_work_item`, `retrieve_work_item`, `retrieve_work_item_by_identifier`, `update_work_item`, `delete_work_item`, `search_work_items` |
| **Epics** | `list_epics`, `create_epic`, `retrieve_epic`, `update_epic`, `delete_epic` |
| **Cycles** | `list_cycles`, `create_cycle`, `retrieve_cycle`, `update_cycle`, `delete_cycle`, `add_work_items_to_cycle`, `remove_work_item_from_cycle`, `list_cycle_work_items`, `transfer_cycle_work_items`, `archive_cycle`, `unarchive_cycle`, `list_archived_cycles` |
| **Modules** | `list_modules`, `create_module`, `retrieve_module`, `update_module`, `delete_module`, `add_work_items_to_module`, `remove_work_item_from_module`, `list_module_work_items`, `archive_module`, `unarchive_module`, `list_archived_modules` |
| **Milestones** | `list_milestones`, `create_milestone`, `retrieve_milestone`, `update_milestone`, `delete_milestone`, `add_work_items_to_milestone`, `remove_work_items_from_milestone`, `list_milestone_work_items` |
| **Initiatives** | `list_initiatives`, `create_initiative`, `retrieve_initiative`, `update_initiative`, `delete_initiative` |
| **Intake** | `list_intake_work_items`, `create_intake_work_item`, `retrieve_intake_work_item`, `update_intake_work_item`, `delete_intake_work_item` |
| **Labels** | `list_labels`, `create_label`, `retrieve_label`, `update_label`, `delete_label` |
| **States** | `list_states`, `create_state`, `retrieve_state`, `update_state`, `delete_state` |
| **Work Item Extras** | `list_work_item_activities`, `retrieve_work_item_activity`, `list_work_item_comments`, `create_work_item_comment`, `update_work_item_comment`, `delete_work_item_comment`, `list_work_item_links`, `create_work_item_link`, `update_work_item_link`, `delete_work_item_link`, `list_work_item_relations`, `create_work_item_relation`, `remove_work_item_relation`, `list_work_logs`, `create_work_log`, `update_work_log`, `delete_work_log` |
| **Work Item Types/Properties** | `list_work_item_types`, `create_work_item_type`, `retrieve_work_item_type`, `update_work_item_type`, `delete_work_item_type`, `list_work_item_properties`, `create_work_item_property`, `retrieve_work_item_property`, `update_work_item_property`, `delete_work_item_property` |
| **Pages** | `retrieve_workspace_page`, `retrieve_project_page`, `create_workspace_page`, `create_project_page` |
| **Workspace** | `get_workspace_members`, `get_workspace_features`, `update_workspace_features` |
| **Users** | `get_me` |

30 Plane projects are bootstrapped and available across agents (bootstrapped via
`~/repos/gitea/host-forge-scripts/scripts/plane-bootstrap-projects.py`). See
`host-forge/plane-projects.md` for the project ID reference used in agent CLAUDE.md files.

## Dependencies

- Plane self-hosted at `http://127.0.0.1:3007` (must be running for token validation)
- `~/venvs/plane-mcp/` Python venv
- `~/.secrets/plane.env` (PLANE_TOKEN_RESEARCH, PLANE_WORKSPACE)

## Operations

```bash
# Status
pm2 show plane-mcp

# Logs
pm2 logs plane-mcp --lines 50

# Restart
pm2 restart plane-mcp

# Manual test
curl -s http://localhost:8495/health
```

## scoped-mcp Wiring

Registered in all 5 agent manifests. Per-agent tool allowlists restrict the surface:

| Manifest | Access |
|----------|--------|
| `sysadmin-agent.yml` | Full access (no allowlist) |
| `developer-agent.yml` | Full access (no allowlist) |
| `research-agent.yml` | `list_projects`, `list_work_items`, `search_work_items`, `retrieve_work_item`, `create_work_item`, `create_intake_work_item` |
| `security-agent.yml` | `list_projects`, `list_work_items`, `retrieve_work_item`, `create_work_item`, `create_intake_work_item` |
| `writer-agent.yml` | `list_projects`, `list_work_items`, `retrieve_work_item`, `create_work_item` |

All manifests inject `Authorization: Bearer ${PLANE_TOKEN}` and `x-workspace-slug: ${PLANE_WORKSPACE}` headers. Each agent uses its own `PLANE_TOKEN` variable sourced from the appropriate env file.

## Security Notes

- `PlaneTokenValidator` middleware validates each request's Bearer token against the Plane
  API (`/api/v1/users/me/`) before FastMCP processes it — defence-in-depth over the upstream
  library's presence-only check. (Audit: 2026-06-03/plane-mcp-2026-06, L1 resolved)
- `diskcache` 5.6.3 CVE-2025-69872 accepted — no fix released at time of deploy; localhost-only
  service, not externally exposed. (Audit: 2026-06-03/plane-mcp-2026-06, L3 accepted)
- API keys are never logged; injected at request time via scoped-mcp header injection
