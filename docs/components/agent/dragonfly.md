# Dragonfly

Dragonfly is a Redis-compatible in-memory data store deployed across multiple forge stacks.
Each instance serves a different purpose — agent session state, search caching, or
application caching. Forge runs 3 Dragonfly instances alongside 4 Valkey instances.

## Instances

| Instance | Port | Stack | Network | Consumers |
|----------|------|-------|---------|-----------|
| **agent-dragonfly** | `127.0.0.1:6380` | `~/docker/agent-platform/` | forge-net, grafana-datasources | Agent session state, HITL gate, scoped-mcp |
| **searxng-dragonfly** | `127.0.0.1:6381` | `~/docker/searxng/` | searxng-internal, forge-net, grafana-datasources | SearXNG cache (db0), searxng-mcp cache (db1) |
| **langfuse-dragonfly** | internal only | `~/docker/langfuse/` | langfuse-internal, grafana-datasources | Langfuse worker/web cache |

All three run `docker.dragonflydb.io/dragonflydb/dragonfly:v1.37.2` (pinned) with
`--requirepass` authentication.

### Related Valkey/Redis Instances

| Instance | Stack | Network | Consumers |
|----------|-------|---------|-----------|
| **oqp-valkey** | agent-platform | oqp-internal, grafana-datasources | Ollama queue proxy embedding cache |
| **patchmon-valkey** | patchmon | patchmon-internal, grafana-datasources | PatchMon cache |
| **plane-valkey** | plane | plane-internal, grafana-datasources | Plane project management |
| **firecrawl-redis** | crawler | internal | Firecrawl job queue |

All 7 instances are visible to Grafana via the `grafana-datasources` network for monitoring.

## agent-dragonfly (Primary)

| Setting | Value |
|---------|-------|
| Image | `docker.dragonflydb.io/dragonflydb/dragonfly:v1.37.2` (pinned) |
| Container | `agent-dragonfly` |
| Port | `127.0.0.1:6380` → container 6379 (localhost-only) |
| Max memory | 8 GB (`--maxmemory=8gb`) |
| Threads | 4 (`--proactor_threads=4`) |
| Data dir | `/opt/appdata/agent-platform/dragonfly` |
| Network | `forge-net` |
| Auth | `--requirepass ${DRAGONFLY_PASSWORD}` |
| Compose | `~/docker/agent-platform/docker-compose.yml` |

**Thread minimum:** Dragonfly requires at least 256 MB of maxmemory per proactor thread.
With `--maxmemory=8gb` and `--proactor_threads=4`, each thread gets 2 GB. Reducing maxmemory
below 1 GB with 4 threads will cause startup failure.

## Authentication

Password in `~/docker/agent-platform/.env` (chmod 600) — used by the compose stack.

Agents access Dragonfly through scoped-mcp, which reads the connection URL from the agent's
`.env` file (`DRAGONFLY_URL=redis://:<password>@127.0.0.1:6380`). Only the sysadmin agent
currently uses Dragonfly directly (for HITL state).

## What It's Used For

agent-dragonfly stores:
- **HITL gate state** — pending approval records for sysadmin high-impact tool calls
- **Domain caching** — searxng-mcp domain metadata from web search results
- **Session cursors** — watermarks and dedup state between scheduled agent invocations

It is **not** appropriate for:
- Anything that must survive a restart
- Secrets or credentials
- Data that should be auditable (use NATS or the agent-bus event log)

All keys are TTL-bound. Dragonfly does not persist between restarts unless the data volume
is intact.

## Container Hardening

- Runs as `user: "1000:1000"` (matches host `ted` uid)
- `cap_drop: [ALL]` — no Linux capabilities
- `security_opt: [no-new-privileges: "true"]`
- Data directory (`/opt/appdata/agent-platform/dragonfly`) owned by `ted:ted`

## Backup

Not backed up. Dragonfly is a hot cache — all values have TTLs and are rebuildable on next
invocation. If the container restarts, agents recompute their state on the next run.

## Gotchas

- `--proactor_threads=4` with `--maxmemory=8gb` gives 2 GB per thread. Minimum viable:
  256 MB per thread. Fewer threads or less memory will fail at startup.
- The `healthcheck` in the compose file uses `redis-cli -p 6379` (container-internal port),
  not 6380.
- `forge-net` membership means other forge containers can reach Dragonfly — auth is the only
  protection for non-localhost access.

## Related Docs

- [scoped-mcp.md](scoped-mcp.md) — HITL state backend configuration
- [phase-7-agent-infrastructure.md](../../phases/phase-7-agent-infrastructure.md) — Phase 7 build context
