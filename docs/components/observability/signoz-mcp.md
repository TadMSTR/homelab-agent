# signoz-mcp

signoz-mcp is a read-only FastMCP server that wraps the SigNoz HTTP API, giving the
sysadmin agent structured access to forge observability data — services, traces, logs,
metrics, and alert rules — without exposing SigNoz write endpoints.

- **Package:** `signoz-mcp` v0.1.3 (TadMSTR/signoz-mcp)
- **Repo:** `/home/ted/repos/personal/signoz-mcp/`
- **Venv:** `/home/ted/repos/personal/signoz-mcp/.venv/`
- **Transport:** streamable-http — `127.0.0.1:8492` (PM2, `ecosystem.config.js`)
- **SigNoz URL:** `http://localhost:8080` (SigNoz stack on forge-net)
- **Auth:** `SIGNOZ_API_KEY` — injected from `~/.secrets/forge.env` (key: `SIGNOZ_KEY`)
- **Log:** `/opt/appdata/signoz-mcp/logs/signoz-mcp.log` (JSON, structlog; dir 0750, file 0640)

## Installation

```bash
cd /home/ted/repos/personal
git clone https://github.com/TadMSTR/signoz-mcp.git
cd signoz-mcp
python3 -m venv .venv
.venv/bin/pip install -e .
```

## Launch

PM2 via `ecosystem.config.js` in the repo root:

```js
env: {
  SIGNOZ_URL: "http://localhost:8080",
  SIGNOZ_API_KEY: process.env.SIGNOZ_API_KEY,   // injected from forge.env at PM2 start
  SIGNOZ_QUERY_VERSION: "v3",
  FASTMCP_TRANSPORT: "streamable-http",
  FASTMCP_PORT: "8492",
  FASTMCP_HOST: "127.0.0.1",
}
```

`SIGNOZ_API_KEY` is sourced from `~/.secrets/forge.env` (key: `SIGNOZ_KEY`) before `pm2 start`. The Python launch script `/home/ted/scripts/run-signoz-mcp.sh` is retained as a fallback — it handles `forge.env` special characters that bash `source` misinterprets.

## Tools (9, all read-only)

| Tool | Description |
|------|-------------|
| `list_services` | All registered service names — returns `list[str]` (not RED metrics; API changed in SigNoz v0.118+) |
| `count_errors` | Error span count grouped by service over a time range |
| `search_traces` | Filter traces by service, error state, minimum duration |
| `tail_logs` | Recent logs for a service filtered by severity |
| `count_log_errors` | Error/warn log rate over time |
| `query_metric` | Named metric with optional label filter (metric_name validated) |
| `list_metrics` | All ingested metric names |
| `list_alert_rules` | Alert rules and current firing state |
| `get_health` | Connectivity check |

No ingest, delete, or configuration endpoints are exposed. Read-only surface by design.

`SIGNOZ_QUERY_VERSION` is allowlisted to `v3` / `v5` at startup. `metric_name` in
`query_metric` is validated against `[a-zA-Z0-9._:/-]+`.

## scoped-mcp Wiring

Registered in three agent manifests under `~/.claude/manifests/`:

| Manifest | Access |
|----------|--------|
| `sysadmin-agent.yml` | Yes |
| `research-agent.yml` | Yes |
| `security-agent.yml` | Yes |

Writer and developer agents do not have access.

## Observability

Structured JSON logs written to `/opt/appdata/signoz-mcp/logs/signoz-mcp.log` via structlog.
Log level controlled by `LOG_LEVEL` env var (default: INFO). OTEL tracing available opt-in
via `OTEL_EXPORTER_OTLP_ENDPOINT`.

## Security Notes

- `SIGNOZ_API_KEY` is injected at runtime — never appears in any config file or log output
- `forge.env` is read-only (`600` permissions), never modified by the launcher
- `SIGNOZ_QUERY_VERSION` is validated at startup against an allowlist (`frozenset({"v3", "v5"})`)
- `metric_name` in `query_metric` validated against regex allowlist (v0.1.2)
- `label_filter` validated against `[a-zA-Z0-9_.='<>!()\[\]\s,]+` allowlist (v0.1.3); previously capped at 500 chars
- Log dir 0750, log file 0640 (v0.1.3)
- Security audits: `forge-observer-mcps-deploy` (2026-05-27, 2 Low), `signoz-mcp-deploy-2026-05` (2026-05-30, resolved)
