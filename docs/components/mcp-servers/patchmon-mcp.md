# patchmon-mcp

FastMCP Python MCP server wrapping the PatchMon REST API. Gives forge agents structured
read access to host patch state and (via JWT) the ability to schedule and approve patch
runs through PatchMon's admin API.

- **Version:** 0.1.1
- **Repo:** `TadMSTR/patchmon-mcp` (public)
- **Transport:** stdio (PM2-managed)
- **Port:** none — stdin/stdout only
- **Auth:** dual-auth (see below)
- **Agents:** all 5 forge agents via scoped-mcp `patchmon` module

## Tools

### Integration API (Basic Auth)

Read-only tools using PatchMon's Integration API credentials:

| Tool | Description |
|------|-------------|
| `list_hosts` | List all enrolled hosts with patch status summary |
| `get_host` | Get details for a specific host by ID |
| `get_host_packages` | List installed packages on a host, optionally filtered by update state |
| `get_host_stats` | Patch statistics for a host (total/pending/critical counts) |
| `get_package_reports` | CVE and advisory reports for packages across hosts |
| `get_agent_queue` | Current agent task queue (patch runs pending execution) |

### Admin API (JWT)

Privileged tools using JWT authentication (token cached and refreshed automatically):

| Tool | Description |
|------|-------------|
| `preview_patch_schedule` | Preview what would be patched in a scheduled run |
| `trigger_dry_run` | Start a dry-run to preview patch effects without applying |
| `get_patch_run` | Poll status and results of a patch run by ID |
| `list_patch_runs` | List recent patch runs with status |
| `trigger_patch` | Trigger a live patch run (requires operator approval in workflow) |
| `approve_patch_run` | Approve a pending patch run after dry-run review |

## Dual-Auth Model

patchmon-mcp uses two separate credential sets for two separate APIs:

| API | Credential type | Source | Permission level |
|-----|----------------|--------|-----------------|
| Integration API | Basic Auth (`TOKEN_KEY:TOKEN_SECRET`) | `forge.env` | Read-only |
| Admin API | JWT (`ADMIN_USER` + `ADMIN_PASS`) | `forge.env` | Full patch control |

JWT tokens are cached in memory and refreshed automatically on 401. The `TOKEN_KEY` and
`TOKEN_SECRET` for the Integration API are generated per-project in the PatchMon UI at
**Settings → API Tokens**.

## Recommended Workflow: Dry-Run First

The expected agent workflow for patching a host:

```
trigger_dry_run(host_id=...) → {run_id: "abc123"}
    ↓
get_patch_run(run_id="abc123") → {status: "complete", packages: [...]}
    ↓  (review results with operator)
approve_patch_run(run_id="abc123") → {status: "approved"}
    ↓
trigger_patch(host_id=...) → live run
```

`trigger_patch` is intentionally separated from `approve_patch_run` to require an explicit
operator decision between dry-run review and live execution.

## scoped-mcp Registration

Registered in all 5 agent manifests at `~/.claude/manifests/<agent>.json` as module type
`mcp_proxy` with Basic Auth + JWT credentials sourced from the environment:

```json
{
  "name": "patchmon",
  "type": "mcp_proxy",
  "url": "http://patchmon-mcp/mcp"
}
```

Credentials flow from `forge.env` → `run-scoped-mcp.sh` → scoped-mcp environment →
patchmon-mcp subprocess.

## Observability

Structured logging (structlog, JSON-L) is always on. Logs go to **stderr and a file simultaneously** — no configuration required.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/patchmon-mcp/logs/patchmon-mcp.log` | Log file path. Default is baked in; override to redirect. |
| `LOG_LEVEL` | `INFO` | Structured log level. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Enable OTEL tracing (`pip install patchmon-mcp[otel]`). |
| `INFLUXDB_URL` + `INFLUXDB_TOKEN` | — | Enable InfluxDB metric emission (`pip install patchmon-mcp[influxdb]`). |
| `NATS_URL` | — | Enable NATS metric publishing (`pip install patchmon-mcp[nats]`). |

The log directory is created automatically on startup.

**v0.1.0 → v0.1.1:** Logs were incorrectly written to stdout in v0.1.0, corrupting the MCP
JSON-RPC stream. Fixed in v0.1.1 — all log output now goes to stderr only (and the log file).

## Security

From audit 2026-05-25 (2 Low findings, both resolved):

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| L1 | Low | `.env` and `*.env` missing from `.gitignore` | Added to `.gitignore` (commit `4cc942e`) |
| L2 | Low | `PatchMonError(0, …)` for config errors — status code 0 not meaningful | `PatchMonConfigError` subclass added; raises without a status code (commit `4cc942e`) |

## Related Docs

- [patchmon.md](../cicd/patchmon.md) — PatchMon server (the wrapped service)
- [forge-patchmon-migration.md](../../phases/) — build phase doc
- [forge-agent-mcp-restore.md](../../phases/forge-agent-mcp-restore.md) — scoped-mcp wiring
