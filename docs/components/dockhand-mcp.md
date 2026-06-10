# dockhand-mcp

FastMCP Python MCP server wrapping the Dockhand REST API. Gives forge agents structured
access to Docker container and stack state, with the ability to take container and
compose stack actions.

- **Version:** 0.1.1
- **Repo:** `TadMSTR/dockhand-mcp` (public)
- **Transport:** stdio (PM2-managed)
- **Port:** none — stdin/stdout only
- **Auth:** Bearer token (`DOCKHAND_API_TOKEN` from `forge.env`)
- **Agents:** all 5 forge agents via scoped-mcp `dockhand` module

## Tools

| Tool | Description |
|------|-------------|
| `get_health` | Dockhand server health and version |
| `list_containers` | List all containers with status, optionally filtered by environment |
| `list_stacks` | List Docker Compose stacks managed by Dockhand |
| `container_action` | Perform an action on a container: `start`, `stop`, `restart`, `pause`, `unpause`, or `remove` |
| `stack_action` | Perform an action on a stack: `start`, `stop`, `restart`, or `deploy` |
| `check_updates` | Check for available image updates across containers |
| `update_container` | Pull and restart a container with the latest image |
| `scan_image` | Run a vulnerability scan on a container image |
| `get_activity` | Recent Dockhand activity log (deployments, restarts, etc.) |

## Input Validation

`container_id` and `stack_name` parameters are validated against a safe-ID regex before
being interpolated into URL paths:

```python
_SAFE_ID = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_\-\.]*$')
```

Values that don't match are rejected with a clear error rather than being passed to
the API. This prevents path traversal (e.g., `../health`) via tool parameters.

Query parameters use `httpx`'s `params=` dict rather than f-string interpolation, which
prevents query injection via values containing `&`.

## scoped-mcp Registration

Registered in all 5 agent manifests at `~/.claude/manifests/<agent>.json` as module type
`mcp_proxy` with Bearer token credentials sourced from the environment:

```json
{
  "name": "dockhand",
  "type": "mcp_proxy",
  "url": "http://dockhand-mcp/mcp"
}
```

## Observability

Structured logging (structlog, JSON-L) is always on. Logs go to **stderr and a file simultaneously** — no configuration required.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/dockhand-mcp/logs/dockhand-mcp.log` | Log file path. Default is baked in; override to redirect. |
| `LOG_LEVEL` | `INFO` | Structured log level. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Enable OTEL tracing (`pip install dockhand-mcp[otel]`). |
| `INFLUXDB_URL` + `INFLUXDB_TOKEN` | — | Enable InfluxDB metric emission (`pip install dockhand-mcp[influxdb]`). |

The log directory is created automatically on startup.

## Security

From audit 2026-05-25 (3 findings):

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | GitHub PAT embedded in `.git/config` remote URL | Remote switched to SSH (`git remote set-url`); PAT rotation pending (manual) |
| L1 | Low | `container_id` / `stack_name` unsanitized in URL paths (path traversal) | `_SAFE_ID` regex validation added to `container_action`, `stack_action`, `update_container` (commit `8b3f729`) |
| L2 | Low | `environment_id` f-string in URL query (query injection) | Switched to `httpx params=` dict in `list_containers` and `list_stacks` (commit `8b3f729`) |

**Note on M1:** The PAT has been removed from `.git/config` by switching to SSH remote.
PAT rotation (GitHub UI action) remains a pending manual step.

## Related Docs

- [dockhand.md](dockhand.md) — Dockhand service (the wrapped service)
- [forge-agent-mcp-restore.md](../phases/forge-agent-mcp-restore.md) — scoped-mcp wiring
