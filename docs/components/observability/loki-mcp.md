# loki-mcp

loki-mcp is a read-only FastMCP server that wraps Loki's LogQL HTTP API, giving the
security and sysadmin agents programmatic access to forge log data without exposing
Loki's ingest endpoints. It speaks Loki's tenant model: every request carries an
`X-Scope-OrgID` header, and agents can switch tenant per call within an allowlist.

- **Package:** `loki-mcp` v0.2.0 (TadMSTR/loki-mcp)
- **Repo:** `~/repos/personal/loki-mcp/`
- **Venv:** `/opt/venvs/loki-mcp/` (non-editable install, managed by `venv-deploy.sh`)
- **Transport:** stdio (launched via `~/scripts/run-loki-mcp.sh` as a child of scoped-mcp)
- **Loki URL:** `http://localhost:3100` (port 3100 published to `127.0.0.1:3100` in `docker/observability/docker-compose.yml`)

## Installation

v0.2.0 moved the package to a `src/` layout and changed the dependency set
(FastMCP 3 → 4), so upgrading from 0.1.x is a reinstall, not a restart.

On forge the venv is built by the shared deploy script rather than by hand:

```bash
~/scripts/venv-deploy.sh --service loki-mcp --no-restart
```

`--no-restart` because loki-mcp has no PM2 process of its own (see
[Restarting](#restarting)). For a standalone install:

```bash
git clone https://github.com/TadMSTR/loki-mcp.git
cd loki-mcp
git checkout v0.2.0
uv sync --frozen            # or: python3 -m venv .venv && .venv/bin/pip install .
```

The `otel` extra (`pip install 'loki-mcp[otel]'`) is only needed when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set. forge does not set it for loki-mcp, so the extra
is not installed.

## Launch Script

`~/scripts/run-loki-mcp.sh`:

```bash
#!/bin/bash
set -euo pipefail
export LOKI_URL="http://localhost:3100"
export LOKI_ORG_ID="forge|fake"
export LOKI_TENANTS="forge|fake,argus"
exec /opt/venvs/loki-mcp/bin/python3 -m loki_mcp.server
```

No secrets are involved: the tenant header routes requests, it does not authenticate
them (see [Tenant model](#tenant-model)).

## Tenant Model

forge's Loki runs with `auth_enabled: true` and `multi_tenant_queries_enabled: true`.
Every request must carry `X-Scope-OrgID`; a client that sends no tenant header is
rejected with `401 no org id`. loki-mcp turns that 401 into an error naming
`LOKI_ORG_ID`.

| Tenant | Contents |
|--------|----------|
| `forge` | forge's own logs, written by forge's Alloy |
| `argus` | a second fleet host's logs; the ingest relay forces this tenant per entry, so the pushing client never chooses it |
| `fake` | everything written before multi-tenancy was switched on (Loki's default tenant when auth is off). Read-only bridge; drops out of the launcher once it ages out of retention (around 2026-12-09) |

How loki-mcp uses this:

- **`LOKI_ORG_ID`** is the header sent on every call that does not pass `tenant`. It may
  name several tenants joined by `|`. forge sets `forge|fake`, so by default agents see
  forge's current logs and the pre-switch history in one query. Results that span
  tenants keep Loki's `__tenant_id__` label so the source tenant stays visible.
- **`LOKI_TENANTS`** is the allowlist for the per-call `tenant` argument:
  comma-separated, each entry one complete header value. With forge's
  `forge|fake,argus`, `tenant="argus"` and `tenant="forge|fake"` are accepted;
  `tenant="forge"` or `tenant="fake"` on their own are not, because the match is exact.
  A value not on the list is an error, never a pass-through. With `LOKI_TENANTS` unset,
  the `tenant` argument is refused entirely.
- **Tenant IDs are validated** against Loki's rules (1–150 characters from
  `0-9 A-Z a-z ! - _ . * ' ( )`). **A colon is rejected**: Loki stops reading the header
  at a colon, so `forge:x` would silently read tenant `forge`.
- **Endpoint coverage.** Every endpoint loki-mcp calls accepts a multi-tenant header
  (measured on Loki 3.7.6). Loki's `tail` and `push` endpoints do not, and loki-mcp
  calls neither.

The header is a routing key, not a credential. Isolation between tenants on the write
side rests on Loki's port being localhost-only, the ingest network, and the reverse
proxy clearing any client-supplied `X-Scope-OrgID`. On the read side, `LOKI_TENANTS`
bounds what an agent can ask for.

## Tools (10, all read-only)

Every tool carries the MCP `readOnlyHint` / `idempotentHint` annotations and takes an
optional `tenant` argument (see above). Time arguments accept a relative duration
(`-1h`, `-30m`, `-7d`), ISO 8601 (no offset means UTC), or `now`. `step` takes a
Prometheus duration (`30s`, `5m`, `1h30m`) or a number of seconds.

| Tool | Loki endpoint | Key parameters (defaults) | Returns |
|------|---------------|---------------------------|---------|
| `query_logs` | `query_range` | `logql`, `start`, `end="now"`, `limit=100`, `direction="backward"` | Log lines `{ts, line, labels}`, merged across streams in time order |
| `query_aggregate` | `query_range` | `logql`, `start`, `end="now"`, `step="5m"` | Metric series `{labels, values: [{ts, value}]}` |
| `query_instant` | `query` | `logql`, `at="now"` | Metric samples `{labels, ts, value}` at one point in time |
| `get_labels` | `labels` | `start="-24h"`, `end="now"` | Label names |
| `get_label_values` | `label/<name>/values` | `label`, `start="-24h"`, `end="now"` | Values of one label |
| `get_streams` | `series` | `selector="{}"`, `start="-1h"`, `end="now"` | Label sets of the matching streams |
| `get_volume` | `index/volume`, `index/volume_range` (when `step` is set) | `selector`, `start="-1h"`, `end="now"`, `limit=100`, `target_labels`, `aggregate_by="series"\|"labels"`, `step` | Bytes ingested per stream or label, largest first |
| `get_stats` | `index/stats` | `selector`, `start="-1h"`, `end="now"` | Streams, chunks, entries, bytes (index estimate) |
| `get_detected_fields` | `detected_fields` | `selector`, `start="-1h"`, `end="now"`, `line_limit=100` | Parsed fields and structured-metadata keys, with type and cardinality |
| `tail_recent` | `query_range` | `selector`, `n=50` | The newest N lines (24 h lookback; not a live tail) |

**Output shape (changed in v0.2.0).** Every tool returns an object, not a bare list:
the result under a named key (`lines`, `series`, `samples`, `labels`, `values`,
`streams`, `volumes`, `fields`) plus `count`, the `tenant` header that was sent, and
`truncated`. When a result is cut to fit the size budget, a `note` says how much was
left out. Labels are always nested under `labels`, never spread into the row, so a
pushed label called `line`, `ts` or `value` cannot overwrite the log line, timestamp or
sample.

**Validation.** `limit`, `n` and `line_limit` must be 1–1000; `direction` must be
`backward` or `forward`; selectors must start with `{`; `start` must be before `end`.
Bad arguments are rejected before anything is sent to Loki. A metric expression sent to
`query_logs` (or a log query sent to `query_aggregate` / `query_instant`) returns an
error naming the right tool, and LogQL errors come back with Loki's own message.

No ingest, push, delete or admin endpoints are exposed. This is a read-only surface by
design.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOKI_URL` | `http://localhost:3100` | Loki base URL |
| `LOKI_ORG_ID` | unset (no header) | Default `X-Scope-OrgID`; `\|`-joined for several tenants. Unset only works against single-tenant Loki |
| `LOKI_TENANTS` | unset (`tenant` refused) | Comma-separated allowlist of exact values for the per-call `tenant` argument |
| `LOKI_TIMEOUT` | `30` | Seconds per Loki request (0–600) |
| `LOKI_MAX_BODY_BYTES` | `33554432` (32 MiB) | Largest Loki response read; a bigger one is refused before parsing |
| `LOKI_MAX_LINE_CHARS` | `2000` | Longer log lines are cut and marked `line_truncated_chars` |
| `LOKI_MAX_RESPONSE_CHARS` | `100000` | Size budget for one tool result; beyond it items are dropped and `truncated` is set |
| `LOG_LEVEL` | `INFO` | Server log level |
| `LOG_FILE` | `/opt/appdata/loki-mcp/logs/loki-mcp.log` | Rotating log file; empty for stderr only |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset | Enables one span per Loki request (needs the `otel` extra) |

An invalid value (a bad tenant ID, a non-numeric or out-of-range `LOKI_TIMEOUT`) stops
the server at startup with exit code 2 and the variable named, rather than failing on an
agent's first call.

## scoped-mcp Wiring

loki-mcp is a module in the security and sysadmin agent manifests:

```yaml
loki-mcp:
  type: mcp_proxy
  config:
    command: ~/scripts/run-loki-mcp.sh
```

The other agents (research, developer, writer) do not have access — log data is
security/ops-relevant only. To confirm the current set:

```bash
grep -l 'run-loki-mcp' /etc/forge/manifests/*.yml
```

## Restarting

loki-mcp is not a daemon and has no PM2 entry: each scoped-mcp broker spawns it as a
stdio subprocess. Restarting it means restarting every broker whose manifest declares it
(today `scoped-mcp-sysadmin` and `scoped-mcp-security`). scoped-mcp freezes the tool
list at broker start, so a new loki-mcp version (or new tools) only becomes visible to
agents after those broker restarts.

## Observability

Structured logging (structlog, JSON-L) is always on. Logs go to **stderr and a file
simultaneously**.

- The log file rotates at 5 MB, keeping 3 backups; every file is mode 600. The log
  directory is created on startup.
- One line per Loki request: path, tenant, status, duration. The LogQL text is logged
  only at `DEBUG`.
- `httpx`, `httpcore` and the MCP SDK's request logger are held at `WARNING`.
- With `OTEL_EXPORTER_OTLP_ENDPOINT` set (and the `otel` extra installed), one span is
  emitted per Loki request. Before v0.2.0 the OTEL setup was dead code and emitted
  nothing.

## Security Notes

- Read-only: only `GET` requests to Loki's query endpoints; no ingest tools exposed
  (SC-07 confirmed in security audit 2026-05-26).
- Tenant access is an allowlist: with `LOKI_TENANTS` unset an agent can only read the
  tenant(s) in `LOKI_ORG_ID`.
- Bounded reads: Loki's response is capped at `LOKI_MAX_BODY_BYTES` before parsing, and
  the result handed to the agent is cut to `LOKI_MAX_RESPONSE_CHARS`.
- Errors: a 4xx from Loki is returned with Loki's message (the agent needs it to fix the
  query); a 5xx is returned as a generic error with its body sent to the log.
  Credentials in `LOKI_URL` are never echoed.
- No outbound calls except Loki (and the OTLP endpoint, if set). FastMCP's startup
  banner, which checks PyPI for updates, is disabled.
- stdio transport: no network binding, no external exposure.
- Loki port 3100 is bound to `127.0.0.1:3100` only — localhost-only, no reverse proxy.

## Related Docs

- [scoped-mcp.md](../agent/scoped-mcp.md) — agent proxy that loads loki-mcp
- [grafana-alloy.md](grafana-alloy.md) — the Grafana + Loki + Alloy stack loki-mcp queries
- [loki-mcp README](https://github.com/TadMSTR/loki-mcp) — upstream reference and CHANGELOG
