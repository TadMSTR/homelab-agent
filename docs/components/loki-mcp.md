# loki-mcp

loki-mcp is a read-only FastMCP server that wraps Loki's LogQL HTTP API, giving the
security and sysadmin agents programmatic access to forge log data without exposing
Loki's ingest endpoints.

- **Package:** `loki-mcp` v0.1.1 (TadMSTR/loki-mcp)
- **Repo:** `/home/ted/repos/personal/loki-mcp/`
- **Venv:** `/home/ted/repos/personal/loki-mcp/.venv/`
- **Transport:** stdio (launched via `run-loki-mcp.sh`)
- **Loki URL:** `http://localhost:3100` (port 3100 published to `127.0.0.1:3100` in docker/observability/docker-compose.yml)

## Installation

```bash
cd /home/ted/repos/personal
git clone https://github.com/TadMSTR/loki-mcp.git
cd loki-mcp
git checkout v0.1.1
python3 -m venv .venv
.venv/bin/pip install -e .
```

## Launch Script

`/home/ted/scripts/run-loki-mcp.sh`:

```bash
#!/bin/bash
set -euo pipefail
export LOKI_URL="http://localhost:3100"
exec /home/ted/repos/personal/loki-mcp/.venv/bin/python3 -m loki_mcp.server
```

## Tools (6, all read-only)

| Tool | Description |
|------|-------------|
| `query_logs` | LogQL instant query — returns matching log lines |
| `query_aggregate` | LogQL metric query — returns aggregated values |
| `get_labels` | List all label names in Loki |
| `get_label_values` | List values for a specific label |
| `get_streams` | List active log streams |
| `tail_recent` | Return recent log entries for a stream |

No ingest, push, or delete endpoints are exposed. This is a read-only surface by design.

## scoped-mcp Wiring

loki-mcp is added as a module to the security and sysadmin agent manifests:

```yaml
loki-mcp:
  type: mcp_proxy
  config:
    command: /home/ted/scripts/run-loki-mcp.sh
```

The other 3 agents (research, developer, writer) do not have access — log data is
security/ops-relevant only.

## Observability

Structured logging (structlog, JSON-L) is always on. Logs go to **stderr and a file simultaneously** — no configuration required.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/loki-mcp/logs/loki-mcp.log` | Log file path. Default is baked in; override to redirect. |
| `LOG_LEVEL` | `INFO` | Structured log level. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Enable OTEL tracing (`pip install loki-mcp[otel]`). |

The log directory is created automatically on startup.

## Security Notes

- Read-only: no ingest tools exposed (SC-07 confirmed in security audit 2026-05-26)
- stdio transport: no network binding, no external exposure
- Loki port 3100 is bound to `127.0.0.1:3100` only — localhost-only, no SWAG proxy

## Related Docs

- [scoped-mcp-forge.md](scoped-mcp-forge.md) — agent proxy that loads loki-mcp
- [forge-agent-setup.md](../phases/forge-agent-setup.md) — agent framework setup
