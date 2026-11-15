# nats-mcp (retired 2026-11-14)

nats-mcp was a read-only FastMCP server that wrapped the NATS HTTP monitoring API, giving agents
visibility into NATS server health, connections, subscriptions, and JetStream status without
requiring NATS credentials. It never opened a NATS client connection, subscribed, or
published — there was no code path from a tool call to the NATS client port (4222).

## Retirement

Retired 2026-11-14 for lack of use: no agent had come to rely on it in the months after its
containerised deploy. The `nats-mcp` service was removed from the `nats` Docker
stack (the NATS server itself is unchanged), its proxy modules were removed from the agent
manifests that had wired it in, its bearer token was deleted from every `.env`, and port 8508
is free. The source repo, [TadMSTR/nats-mcp](https://github.com/TadMSTR/nats-mcp), is archived
on GitHub; its last release was v0.3.0.

NATS health is still visible without it: the monitoring endpoint answers on loopback
(`curl -s http://127.0.0.1:8222/healthz`, or `/varz`, `/connz`, `/jsz`). See [nats.md](nats.md).

## What it was

- **Package:** `nats-mcp` v0.3.0. First tagged release was v0.2.0; 0.1.0 and 0.1.1 in the
  CHANGELOG describe work that was never cut as a release
- **Deployment:** Docker container `nats-mcp`, image `ghcr.io/tadmstr/nats-mcp:v0.3.0`, in the
  `nats` Docker stack
- **Endpoint:** `127.0.0.1:8508` → `/mcp` (bearer-authed) and `/health` (unauthenticated
  liveness probe, exact-path-matched, did not probe NATS)
- **NATS Monitor URL:** `http://nats:8222`, by container name on the shared Docker network
  (the monitoring port itself is unauthenticated by design)
- **Auth:** bearer token, mandatory in HTTP mode (`NATS_MCP_API_TOKEN`, min 16 chars, compared
  with `hmac.compare_digest()`). The server refused to start without it, and refused a
  non-loopback bind unless `NATS_MCP_ALLOW_NONLOOPBACK=1`. `stdio` mode needed no token

### Tools (8, all read-only)

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

`get_connections` returned client IP addresses and `authorized_user` (agent identities). That
disclosure was deliberate and accepted, and it is why the bearer token was mandatory rather
than optional.

### Security notes

- HTTP transport was fail-closed from v0.2.0. Before that it started and served every tool
  unauthenticated when `NATS_MCP_API_TOKEN` was unset; that state never reached a deploy.
- The container joined the shared Docker network to resolve `nats` by name. Bridge networking
  is not directional, so this exposed `nats-mcp:8508` to every co-tenant container; the
  mandatory token was the control, recorded as an accepted risk. The risk went with the
  service.

### Lessons

- Logs went to stdout only by default. An earlier version hardcoded a log directory that did
  not exist on the host; a default log path should be opt-in.
- The OTel exporter needed OTLP over **gRPC (port 4317)**. Pointing it at 4318 (the HTTP
  port) failed silently.
- A monitoring wrapper for a service that already exposes an unauthenticated, loopback-only
  HTTP monitoring API added a token, a container and a network exposure for little gain over
  `curl` against that API.
