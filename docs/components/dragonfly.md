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

**Thread minimum:** Dragonfly requires at least 256 MB of maxmemory per proactor thread. With `--maxmemory=8gb` and `--proactor_threads=4`, each thread gets 2 GB. Reducing maxmemory below 1 GB with 4 threads will cause startup failure.

## Authentication

Password in `~/docker/agent-platform/.env` (600) — used by the compose stack.

`agent-memory-hot.sh` reads `DRAGONFLY_PASSWORD` from the environment and passes it via `-a` flag with `--no-auth-warning`.

## agent-memory-hot.sh

Wrapper script at `~/.helm/bin/agent-memory-hot.sh` providing typed access with automatic key prefixing:

```bash
# Get a value
agent-memory-hot.sh get <agent-type> <key>

# Set a value (default TTL: 1 hour)
agent-memory-hot.sh set <agent-type> <key> <value> [ttl_seconds]

# List all keys for an agent
agent-memory-hot.sh keys <agent-type>
```

Key format: `helm:agent:<agent-type>:<key>`

Examples:
```bash
agent-memory-hot.sh get security last-cisa-check
agent-memory-hot.sh set platform task-cursor abc123 7200
agent-memory-hot.sh keys update
```

## Key Namespace

```
helm:agent:security:*           ← The Watch working state
helm:agent:update:*             ← The Engineers working state
helm:agent:docs:*               ← The Archivists working state
helm:agent:platform:*           ← Platform agent state
helm:agent:<type>:*             ← Any agent type
```

All keys are TTL-bound (default 1 hour). Dragonfly does not persist between restarts unless the data volume is intact.

## What It's Used For

Hot memory is appropriate for:
- Cursors and watermarks between scheduled invocations (e.g., "last checked at X")
- Dedup state (e.g., "already alerted on finding Y")
- Lightweight caches that are cheap to rebuild

It is **not** appropriate for:
- Anything that must survive a restart
- Secrets or credentials
- Data that should be auditable (use NATS or the transit log)

## Backup

Not backed up. Dragonfly is a hot cache — all values have TTLs and are rebuildable on next invocation. If the container restarts, agents will recompute their state on the next run.

## Security Notes

From `forge-q2-sync-deploy` (2026-05-28) security audit (L2, fixed):
- Container hardened with `user: "1000:1000"`, `cap_drop: [ALL]`, `security_opt: [no-new-privileges: "true"]`
- Data directory (`/opt/appdata/dragonfly`) rechowned to `ted:ted` to match container uid

## Gotchas

- `--proactor_threads=4` with `--maxmemory=8gb` gives 2 GB per thread. Minimum viable: 256 MB per thread. Fewer threads or less memory will fail at startup.
- The `healthcheck` in the compose file uses `redis-cli -p 6379` (container-internal port), not 6380.
- `forge-net` membership means other forge containers can reach Dragonfly — auth is the only protection for non-localhost access.

## Related Docs

- [system-agents.md](../../design/system-agents.md) — agents that use hot memory
- [phase-7-agent-infrastructure.md](../phases/phase-7-agent-infrastructure.md) — Phase 7 context
