# nats-mcp

nats-mcp is a read-only FastMCP server that wraps the NATS HTTP monitoring API, giving agents
visibility into NATS server health, connections, subscriptions, and JetStream status without
requiring NATS credentials. It never opens a NATS client connection, subscribes, or
publishes — there is no code path from a tool call to the NATS client port (4222).

- **Package:** `nats-mcp` v0.3.0 (TadMSTR/nats-mcp) — first tagged release was v0.2.0; 0.1.0
  and 0.1.1 in the CHANGELOG describe work that was never cut as a release
- **Repo:** `/home/ted/repos/personal/nats-mcp/`
- **Deployment:** Docker container `nats-mcp`, image `ghcr.io/tadmstr/nats-mcp:v0.3.0`, in the
  `nats` Docker stack (`~/docker/nats/docker-compose.yml`) — **live and healthy**, verified via
  `docker ps` (container start time postdates the v0.3.0 tag commit)
- **Endpoint:** `127.0.0.1:8508` → `/mcp` (bearer-authed) and `/health` (unauthenticated
  liveness probe, exact-path-matched)
- **NATS Monitor URL:** `http://nats:8222` (container-name routing on `forge-net`; the
  monitoring port itself is unauthenticated by design)
- **Auth:** bearer token, mandatory in HTTP mode (`NATS_MCP_API_TOKEN`, min 16 chars) — see
  Security Notes for why this is fail-closed rather than optional
- **Agents:** none currently wired — nats-mcp does not appear in any agent manifest
  (`/etc/forge/manifests/*.yml`, `~/.claude/manifests/`) as of 2026-08-30. Deployed as a
  standalone container, not yet consumed by an agent.

## Tools (8, all read-only)

| Tool | Description |
|------|-------------|
| `get_server_stats` | Server version, uptime, connection count, message rates, memory/CPU |
| `get_connections` | Client connections, open/closed/all — `ip`, `port`, `authorized_user`, `stop`, `reason`, `idle`, `uptime` |
| `get_subscription_stats` | Subscription counts, cache hit rate, fanout stats |
| `get_jetstream_status` | JetStream account totals: stream/consumer counts, bytes, API stats |
| `get_streams` | Per-stream inventory: subjects, message counts, sequences, retention |
| `get_stream` | Full config and state for one stream |
| `get_consumers` | Per-consumer lag: pending, ack-pending, redelivered |
| `get_health` | Health check, with `js_enabled_only` / `js_server_only` variants |

`get_connections(state="closed")` is the tool for diagnosing a misbehaving client — closed
connections carry `reason` (e.g. `"Authorization Violation"`) alongside `authorized_user` and
`ip`. No publish, subscribe, or admin endpoints are exposed. `server_id` is stripped from all
responses to reduce noise.

## Auth — two different ports, two different answers

- **NATS monitoring port (8222):** no credentials required or stored, loopback/container-only,
  unauthenticated by design — unchanged from earlier versions.
- **nats-mcp's own HTTP transport (8508):** fail-closed as of v0.2.0. Refuses to start without
  `NATS_MCP_API_TOKEN` (min 16 chars, checked with `hmac.compare_digest()`), and refuses a
  non-loopback `NATS_MCP_HOST` unless `NATS_MCP_ALLOW_NONLOOPBACK=1`. `stdio` mode needs no
  token and is unaffected.

`get_connections` returns client IP addresses and `authorized_user` (agent identities) — a
deliberate, audited, accepted disclosure — which is why the bearer token on 8508 is mandatory
rather than optional.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `NATS_MONITOR_URL` | `http://localhost:8222` | NATS HTTP monitoring endpoint — in the container this is `http://nats:8222` |
| `NATS_MCP_PORT` | unset | Set to enable HTTP transport. Unset = stdio |
| `NATS_MCP_API_TOKEN` | unset | Bearer token, **required** in HTTP mode, min 16 chars |
| `NATS_MCP_HOST` | `127.0.0.1` | HTTP bind address. Container bakes `0.0.0.0` + the nonloopback opt-in |
| `NATS_MCP_ALLOW_NONLOOPBACK` | unset | Required alongside a non-loopback `NATS_MCP_HOST` |
| `LOG_LEVEL` | `INFO` | structlog log level |
| `LOG_FILE` | unset | Extra file sink. Unset = stdout only, no file/directory created |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset | OTLP **gRPC** endpoint — port 4317, not 4318 |

## Observability

Logs are JSON on stdout only by default (no file, no directory created) — earlier versions
hardcoded a `/opt/appdata/nats-mcp/logs/` path that does not exist on forge; that path claim
was wrong. `httpx`, `httpcore`, `mcp`, `fastmcp`, and `uvicorn`/`starlette` are pinned to
WARNING so `LOG_LEVEL=DEBUG` doesn't drown the service's own lines.

OTel (opt-in via `OTEL_EXPORTER_OTLP_ENDPOINT`, `[otel]` extra) is real as of v0.2.0 — verified
end-to-end against forge's SigNoz. Endpoint must be OTLP over **gRPC (port 4317)**; pointing it
at 4318 (the HTTP port) fails silently.

| Signal | Name | Labels |
|--------|------|--------|
| Span | `nats_mcp.<tool>` | per-call attributes |
| Counter | `nats_mcp.tool.calls` | `tool`, `outcome` |
| Histogram | `nats_mcp.tool.duration` | `tool`, `outcome` |

## Deployment

The container image is the deployment path on forge. `NATS_MONITOR_URL` and
`NATS_MCP_API_TOKEN` are deliberately **not** baked into the image — a `localhost` monitor URL
default would point at the container's own loopback (nothing listens there), and a baked
token would ship a credential in a layer. `NATS_MCP_HOST=0.0.0.0` and
`NATS_MCP_ALLOW_NONLOOPBACK=1` **are** baked, since the container needs a non-loopback bind to
be reachable on `forge-net` at all.

```bash
docker compose -f ~/docker/nats/docker-compose.yml ps nats-mcp
docker compose -f ~/docker/nats/docker-compose.yml logs -f nats-mcp
curl -s http://127.0.0.1:8508/health   # unauthenticated liveness only — does not probe NATS
```

`/health` is liveness, not readiness — it does not probe NATS, so a NATS restart does not mark
the container unhealthy. It is distinct from the `get_health` tool, which does query NATS.

## Port Registry

Port `8508`, loopback-only host publish (`127.0.0.1:8508:8508`); forge-net membership is
outbound-only (resolves the `nats` service name for monitoring calls, accepted risk NE-02). See
`services.md`.

## Security Notes

- HTTP transport fail-closed since v0.2.0 (audit finding MEDIUM-1, 2026-08-30): previously
  started and served every tool unauthenticated when `NATS_MCP_API_TOKEN` was unset.
- `get_connections` exposing client IPs and `authorized_user` is a deliberate, audited, accepted
  disclosure (`accepted-risks.md`) — it is why the bearer token is mandatory in HTTP mode.
- Security audit: `forge-observer-mcps-deploy` — 2 Low findings (both in signoz-mcp, not
  nats-mcp), remediation-complete 2026-05-27. Containerisation build (v0.3.0) audited
  separately; no findings against nats-mcp itself.
