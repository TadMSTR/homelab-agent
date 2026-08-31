# backrest-mcp

FastMCP server wrapping the [Backrest](../foundation/backrest.md) REST API. Gives the
sysadmin agent structured access to backup plan status, snapshot history, and restore
operations against the `atlas-forge` restic repository, without exposing the Backrest
web UI or its bcrypt-hashed admin credentials.

- **Version:** v0.4.0 — observability hardening: single log sink, third-party log
  noise silenced, telemetry failures now visible, NATS fail-fast
- **PM2 process:** `backrest-mcp`
- **Endpoint:** `http://127.0.0.1:8626` — bearer-authed, loopback-only
- **Transport:** streamable-http
- **Wraps:** [backrest](../foundation/backrest.md) (`https://backrest.helmforge.me`,
  native systemd service, REST API on `:9898`)
- **Agents:** sysadmin

## What It Does

Agents query plan status, snapshot lists, and (with operator approval) trigger backups
or restores for any of Backrest's four plans (`forge-agent`, `forge-repos`,
`forge-secrets`, `forge-system` — see [backrest.md](../foundation/backrest.md) for the
schedule and retention of each). Read operations require no gate; `restore_snapshot` is
operator-gated given its blast radius.

## Port / Endpoint

`127.0.0.1:8626`, bearer token required on every request (`BACKREST_MCP_TOKEN`). Not
SWAG-proxied — loopback only, matching the same loopback+bearer-token pattern used by
the other HTTP-transport MCP migrations on forge (dockhand-mcp, githost-mcp per-agent
processes).

## Configuration

| Variable | Purpose |
|----------|---------|
| `BACKREST_MCP_PORT` | Listen port (default `8626`) |
| `BACKREST_URL` | Backrest REST API base (`http://127.0.0.1:9898`) |
| `BACKREST_MCP_TOKEN` | Bearer token clients must present; also used by the health prober |
| `LOG_LEVEL` | structlog log level (default `INFO`) |

## Observability

Exactly one log sink is attached: the file handler when `LOG_FILE` is writable, stderr
otherwise. Before v0.4.0 both a stderr handler and a `LOG_FILE` handler were attached at
once, so every line landed in both `LOG_FILE` *and* PM2's
`~/.pm2/logs/backrest-mcp-error.log` — 8.5 MB and 9.5 MB of near-identical unrotated log.
Anyone who has been reading the PM2 error log for this service should read `LOG_FILE` instead.

`httpx`, `httpcore`, `mcp`, and `nats` are held at WARNING regardless of `LOG_LEVEL` — before
this change third-party wire trace outnumbered the server's own log lines 51,905 to 6.

### Telemetry failure visibility

Optional InfluxDB and NATS telemetry (`INFLUXDB_URL`, `NATS_URL`) is best-effort and never
fails a tool call, but a backend that is *configured and failing* now warns exactly once per
process instead of failing silently:

| Event | Meaning |
|-------|---------|
| `influx_init_failed` | `INFLUXDB_URL` set but the client could not be built. Writes disabled for the process. |
| `influx_write_failed` | The client built but a write failed — **this, not `influx_init_failed`, is what a wrong or unreachable `INFLUXDB_URL` looks like**, because `InfluxDBClient3` connects lazily and so builds successfully against any host. |
| `nats_init_failed` | `NATS_URL` set but the connection failed. Publishes disabled for the process. |
| `nats_transport_error` | First NATS transport error. |
| `nats_publish_failed` | The connection succeeded but a publish failed. |

Each fires at most once per process and carries the exception *class* only — never the URL or
token. `NATS_URL` is currently unset on the deployed service, so the NATS events are latent.

A broken NATS backend now delays a tool call by well under a second instead of ~120s
(`allow_reconnect=False`, 2s connect timeout, 5s overall deadline).

## Dependencies

| Service | Required | Purpose |
|---------|----------|---------|
| [backrest](../foundation/backrest.md) (`:9898`) | Yes | Source REST API — backrest-mcp's own health check fails if this is unreachable or its credentials are stale |
| Atlas NFS mount (`/mnt/atlas/forge`) | Indirect | Backrest's restic repo target; snapshot/restore tools fail if unmounted |

## backrest-mcp-health-prober

A `*/5 * * * *` PM2 cron job (`backrest-mcp-health-prober.py`) calls backrest-mcp's
`get_health` tool directly — bypassing scoped-mcp entirely — specifically to catch the
case where `scoped_mcp_status` reports the module `running` while the *upstream* call
path to Backrest is actually broken (e.g. a rotated Backrest credential backrest-mcp
hasn't picked up yet). A process being alive says nothing about whether its backend
calls succeed; the prober exists to close that gap. On an auth failure it pages
`#sysadmin` directly.

This was added after an incident where `backrest-mcp` returned `401 Unauthorized` on
stale credentials while still showing as a healthy running process — filed as
Vikunja #220 (the credential issue) and #222 (the detection gap the prober closes).

## Operations

```bash
# Status
pm2 status backrest-mcp
pm2 status backrest-mcp-health-prober

# Logs
pm2 logs backrest-mcp --lines 50

# Restart (e.g., after a Backrest credential rotation)
pm2 restart backrest-mcp

# Manual health check (mirrors what the prober does)
curl -s -H "Authorization: Bearer $BACKREST_MCP_TOKEN" http://127.0.0.1:8626/mcp
```

## scoped-mcp Integration

Registered in the sysadmin agent manifest as a loopback bearer-token `mcp_proxy`. Not
yet wired into developer, research, writer, or security manifests.

## Security Notes

Audited under `backrest-mcp-modernization-2026-07` (severity_max: low):

| ID | Status | Note |
|----|--------|------|
| IV-14 | Deferred (Low) | Existing finding — deferred as trusted-local-service-only source |
| BKRST-1 | Accepted (existing) | NATS credential handling — re-confirmed unchanged, not re-filed |
| BKRST-2 | Accepted (existing) | Path validation — re-confirmed unchanged, not re-filed |

The HTTP fail-closed guard and bearer-token log-exposure paths were verified clean (no
findings) in the same audit.

## Related Docs

- [backrest.md](../foundation/backrest.md) — the wrapped Backrest service and its backup plans
- [scoped-mcp.md](../agent/scoped-mcp.md) — manifest structure and agent tool surfaces
