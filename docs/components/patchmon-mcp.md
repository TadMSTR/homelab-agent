# patchmon-mcp

FastMCP Python MCP server wrapping the [PatchMon](https://patchmon.net) REST API. Gives
forge's operator agents structured access to apt patch management across PatchMon-enrolled
hosts: pending updates, dry-run validation, patch approval and execution, job history, and
reboot state.

- **Source:** `~/repos/personal/patchmon-mcp/`
- **PM2 service:** `patchmon-mcp` (forge, stdio transport)
- **Status:** Phase 3 deployment in progress (helm-build)
- **Version:** 0.1.0

## Tools

### Integration API tools (Basic Auth — read-only)

| Tool | Description |
|------|-------------|
| `list_hosts` | All enrolled hosts with update counts, reboot flag, last check-in |
| `get_host` | Full host detail: OS, uptime, kernel, last check-in |
| `get_host_packages` | Packages for a host (`pending_only=True` for updates only) |
| `get_host_stats` | Package and repository statistics |
| `get_package_reports` | Patch history from the Integration API |
| `get_agent_queue` | Current agent job queue status |

### Admin API tools (JWT — patching)

| Tool | Description |
|------|-------------|
| `preview_patch_schedule` | Preview when the next patch would run (no side effects) |
| `trigger_dry_run` | Dry-run for a specific package — simulates with `apt-get -s install` |
| `trigger_patch` | Execute a real patch run (`patch_all` or `patch_package`) |
| `get_patch_run` | Status and result of any patch run; poll after triggering |
| `list_patch_runs` | Patch run history with optional `host_id`/`status` filtering |
| `approve_patch_run` | Approve a `validated` or `pending_approval` run |

## Auth Architecture

PatchMon exposes two distinct APIs, and patchmon-mcp uses both:

- **Integration API** (`/api/v1/api/`): HTTP Basic Auth with scoped credentials
  (`PATCHMON_TOKEN_KEY:PATCHMON_TOKEN_SECRET`). Read-only — host inventory and package data.

- **Admin API** (`/api/v1/`): JWT from `POST /api/v1/auth/login`. Full access including
  all patching operations. Uses `PATCHMON_ADMIN_USER` + `PATCHMON_ADMIN_PASSWORD`.

The JWT is cached in-process and refreshed automatically on 401 or approaching expiry.
Missing Integration API credentials raises a `PatchMonConfigError` at call time (not at
startup), so read-only and patching capabilities can be independently provided.

## Dry-Run Workflow

For safe per-package patching, use the 3-step workflow:

```
1. trigger_dry_run(host_id, "curl")
   → run_id returned; status becomes "validated"

2. get_patch_run(run_id)
   → review shell_output (apt-get -s output), confirm the package change

3. approve_patch_run(run_id)
   → new_run_id returned; real patch run is created and executed
   → get_patch_run(new_run_id) to track completion
```

For patching all pending updates: `trigger_patch(host_id, "patch_all")` directly.
`patch_all` does not support dry-run — `apt-get upgrade` preview requires `patch_package`.

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `PATCHMON_ENDPOINT` | yes | PatchMon base URL |
| `PATCHMON_ADMIN_USER` | yes | Admin username for JWT login |
| `PATCHMON_ADMIN_PASSWORD` | yes | Admin password |
| `PATCHMON_TOKEN_KEY` | for read tools | Integration API credential key |
| `PATCHMON_TOKEN_SECRET` | for read tools | Integration API credential secret |
| `LOG_LEVEL` | no | structlog verbosity (default `INFO`) |
| `LOG_FILE` | no | Log to file path; stdout if unset |
| `INFLUXDB_URL` | no | Enables InfluxDB telemetry when set |
| `INFLUXDB_TOKEN` | no | InfluxDB auth token |
| `INFLUXDB_BUCKET` | no | InfluxDB bucket (default `patchmon-mcp`) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | Enables OTEL traces when set |
| `NATS_URL` | no | Enables NATS event publishing when set |
| `NATS_SUBJECT_PREFIX` | no | NATS subject prefix (default `patchmon`) |

Secrets are injected at PM2 startup via `--env-file`. The forge secrets file uses
Windows `\r\n` line endings — PM2's Go-based env parser handles this correctly. Shell
scripts sourcing the file must strip CRs: `source <(tr -d '\r' < ~/.secrets/forge.env)`.

## Deployment

```bash
cd ~/repos/personal && git clone <repo-url> patchmon-mcp
cd patchmon-mcp
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
pm2 start ecosystem.config.js --env-file ~/.secrets/forge.env
pm2 save
```

Phase 3 of the build (clone, venv, PM2 start, scoped-mcp stub wiring) is handled by
helm-build and is in progress as of 2026-05-25.

## Observability

| Feature | Default | Enable with |
|---------|---------|-------------|
| Structured JSON logging | **ON** | `LOG_LEVEL`, `LOG_FILE` |
| InfluxDB telemetry | off | `INFLUXDB_URL` |
| OTEL traces | off | `OTEL_EXPORTER_OTLP_ENDPOINT` |
| NATS publishing | off | `NATS_URL` |

Follows the standard forge MCP observability pattern — logging always on, telemetry opt-in.

## Related Docs

- [patchmon.md](patchmon.md) *(helm-platform)* — the PatchMon server stack this wraps
- [renovate.md](renovate.md) — companion non-Docker update scanner
