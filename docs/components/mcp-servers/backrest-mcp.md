# backrest-mcp

FastMCP server wrapping the [Backrest](../foundation/backrest.md) REST API. Gives the
sysadmin agent structured access to backup plan status, snapshot history, and restore
operations against the `atlas-forge` restic repository, without exposing the Backrest
web UI or its bcrypt-hashed admin credentials.

- **Version:** v0.3.0 — moved from a per-turn stdio spawn to a single long-lived PM2
  process
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
