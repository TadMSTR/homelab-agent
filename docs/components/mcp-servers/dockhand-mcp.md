# dockhand-mcp

FastMCP Python MCP server wrapping the Dockhand REST API. Gives forge agents structured
access to Docker container and stack state, with the ability to take container and
compose stack actions.

- **Version:** 0.4.0 (`dockhand-mcp-observability-hardening-2026-08-29`) — merged and
  tagged; the doc below describes the merged code, **not necessarily the running host**.
  The redeploy is a separate sysadmin task — check before assuming the PM2 process is
  on 0.4.0.
- **Repo:** `TadMSTR/dockhand-mcp` (public)
- **Transport:** long-lived PM2 HTTP service since 0.3.0, bound to `127.0.0.1:8505/mcp`
  and fronted by scoped-mcp via `url:` (the memsearch-mcp pattern). `stdio` remains the
  local-dev default (`MCP_TRANSPORT` unset).
- **Port:** `127.0.0.1:8505` in `http` mode; none in `stdio` mode
- **Auth:** `http` mode requires `DOCKHAND_MCP_BEARER` (≥ 16 chars) presented as
  `Authorization: Bearer`; startup fails closed on a non-loopback host, a missing
  bearer, or a too-short one. Dockhand itself is reached with `DOCKHAND_API_TOKEN`
  (from `forge.env`).
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

All 9 tools emit an InfluxDB metric as of 0.4.0. `get_health` and `get_activity` did not
before — a 7-of-9 gap with no stated reason (vikunja#574 P6).

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

Since 0.3.0, registered as a `url:`-type `mcp_proxy` pointing at the PM2 HTTP service,
with the bearer token as a header:

```yaml
dockhand-mcp:
  type: mcp_proxy
  config:
    url: http://localhost:8505/mcp
    headers:
      Authorization: "Bearer ${DOCKHAND_MCP_BEARER}"
```

HITL gating on `container_action` / `stack_action` / `update_container` is applied by
scoped-mcp by tool name and is unaffected by the transport.

## Observability

Structured logging (structlog, JSON-L) is always on.

**One log sink, not two (fixed in 0.4.0).** Through 0.3.x, logs went to **stderr and a
file simultaneously** — every line was written to both PM2's `error_file` and `LOG_FILE`,
producing two near-identical unrotated files. That was a defect (vikunja#574 P4), not
configuration: a reader who set up log shipping against the old behaviour needs to
revisit it. As of 0.4.0 there is **one** sink — the file handler wins when `LOG_FILE` is
writable, and stderr is the fallback when it is not (an unwritable path, or `LOG_FILE=''`
to hand the files to PM2 entirely). The fallback is load-bearing: it is what keeps CI and
restricted-permission runners from crashing on an unwritable log path. Rotation is real as
of this build (`/etc/logrotate.d/forge-logs`, daily, rotate 14, copytruncate) — the prior
`ecosystem.config.js` comment claiming rotation "with the pm2-logrotate module" described a
module that was never installed.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/dockhand-mcp/logs/dockhand-mcp.log` | Log file path — the single sink when writable. Set to `''` to hand log files to PM2 and fall back to stderr. |
| `LOG_LEVEL` | `INFO` | This service's own log level. `httpx`, `httpcore`, `mcp`, and `nats` are pinned to `WARNING` regardless of `LOG_LEVEL` (since 0.4.0) — raising `LOG_LEVEL` to `DEBUG` now gets this service's own detail rather than its dependencies' wire trace. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Enables per-tool tracing spans (`dockhand.tool.<name>`, via FastMCP middleware) into SigNoz (`pip install dockhand-mcp[otel]`). |
| `INFLUXDB_URL` + `INFLUXDB_TOKEN` | — | Enable InfluxDB metric emission (`pip install dockhand-mcp[influxdb]`). |
| `NATS_URL` | — | Enable NATS event publishing. |

The log directory is created automatically on startup.

**A configured-but-failing backend warns once and is then disabled for the life of the
process**, rather than being retried on every tool call — `_get_influx()` / `_get_nats()`
now cache a negative sentinel instead of silently `pass`ing on every failed connect. A
backend whose env var is simply *unset* is disabled silently, as before — that is the
intended "off" path, and the distinction matters to anyone reading logs: a warning means
"configured but broken," silence means "not configured." The warning carries the
exception class only, never the URL or token — a NATS URL embeds its own credentials.

**`INFLUXDB_URL` deserves an explicit warning.** `InfluxDBClient3` constructs **lazily**
and never contacts the host, so a wrong URL does not fail at startup — the service comes
up looking healthy, and the failure only surfaces on the first metric write
(`influx_write_failed`). This is not hypothetical: a misconfigured URL went unnoticed for
35 days on forge before this build. The service having started is not evidence that
telemetry works — check for `influx_write_failed` in the logs, not just process uptime.

## Security

From audit 2026-05-25 (3 findings):

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | GitHub PAT embedded in `.git/config` remote URL | Remote switched to SSH (`git remote set-url`); PAT rotation pending (manual) |
| L1 | Low | `container_id` / `stack_name` unsanitized in URL paths (path traversal) | `_SAFE_ID` regex validation added to `container_action`, `stack_action`, `update_container` (commit `8b3f729`) |
| L2 | Low | `environment_id` f-string in URL query (query injection) | Switched to `httpx params=` dict in `list_containers` and `list_stacks` (commit `8b3f729`) |

**Note on M1:** The PAT has been removed from `.git/config` by switching to SSH remote.
PAT rotation (GitHub UI action) remains a pending manual step.

The 0.4.0 observability-hardening audit (2026-08-29) found 0 Critical/High/Medium, 1 Low
(pre-existing `exc_info=True` on three log sites, resolved as a split — the
credential-bearing NATS-shutdown site drops it, the two OTel import sites keep it as a
documented exemption), 2 Info. Full account: `host-forge-knowledge-base/phases/dockhand-mcp-observability-hardening-2026-08-29.md`.

## Related Docs

- [dockhand.md](../foundation/dockhand.md) — Dockhand service (the wrapped service)
- [forge-agent-mcp-restore.md](../../phases/forge-agent-mcp-restore.md) — scoped-mcp wiring
- `host-forge-knowledge-base/phases/dockhand-mcp-observability-hardening-2026-08-29.md` — the 0.4.0 build (private repo, phase doc)
