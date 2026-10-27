# agent-postgres

agent-postgres is the PostgreSQL instance in the agent-platform stack. It holds the
**agent session registry**: which agent sessions ran, which tasks they ran, and an audit
trail of every HITL approval. It sits next to [agent-dragonfly](dragonfly.md) in the same
compose file, and the two split the work. Dragonfly holds the short-lived HITL **gate**
token, which fails closed. Postgres holds the durable **paper trail**, which fails open.

It is a record of what happened. It does not decide anything: no tool call or approval
waits on it.

## Port / Endpoint

| Setting | Value |
|---------|-------|
| Image | `postgres:17-alpine` |
| Container | `agent-postgres` |
| Port | `127.0.0.1:5433` → container 5432 (localhost-only; 5433 avoids clashing with other Postgres instances) |
| Database | `agent_platform` |
| Data dir | `/opt/appdata/agent-platform/postgres` → `/var/lib/postgresql/data` |
| Networks | `forge-net`, `grafana-datasources` |
| Compose | `~/docker/agent-platform/docker-compose.yml` |

## Configuration

Compose environment:

| Var | Purpose |
|-----|---------|
| `POSTGRES_USER` | Owner role (`agent_platform`). Used for admin and migrations only |
| `POSTGRES_PASSWORD` | Set from `${AGENT_POSTGRES_PASSWORD}` in the stack's `.env` (chmod 600) |
| `POSTGRES_DB` | `agent_platform` |

The schema comes from scoped-mcp's `migrations/` directory, applied by hand with `psql`.
The `schema_migrations` table records which migrations have run.

| Migration | Adds |
|-----------|------|
| `0001_agent_session_registry.sql` | `sessions`, `hitl_approvals`, `session_tasks`, `session_usage`, `memory_artifacts`, `schema_migrations` |
| `0002_hitl_resolved_via.sql` | `hitl_approvals.resolved_via` (which channel resolved the approval) |

### Tables

| Table | Holds | Written by |
|-------|-------|-----------|
| `sessions` | One row per launcher-minted run id: agent, transport, room, project dir, status, last seen | scoped-mcp, matrix-dispatcher |
| `hitl_approvals` | Audit row per gated call: agent, tool, state, created/resolved time, `resolved_via`. Stores the **sha256 of the OTP only**, never the plaintext | scoped-mcp (insert + resolve), matrix-dispatcher (link + read state) |
| `session_tasks` | Links a session to the task-queue task it ran (`task_id`, `role`, `build_name`) | scoped-mcp |
| `session_usage`, `memory_artifacts` | Reserved. The schema and insert helpers exist, but nothing writes to them yet | — |

The other tables point at `sessions.session_id` through foreign keys. matrix-dispatcher
writes the `sessions` row before a turn starts, so an approval row created during that
turn always has a session to point at.

### Roles

The services connect as two least-privilege roles, not as the owner:

| Role | Used by | Grants |
|------|---------|--------|
| `agent_registry` | scoped-mcp | SELECT/INSERT/UPDATE on the five registry tables, plus sequence usage. No DELETE and no access to `schema_migrations` |
| `dispatcher_registry` | matrix-dispatcher | SELECT/INSERT/UPDATE on `sessions`, SELECT/UPDATE on `hitl_approvals`. No access to the other tables |

Each consumer reads its connection string from its own `AGENT_REGISTRY_DSN` env var
(`postgresql://<role>:<password>@127.0.0.1:5433/agent_platform`).

## Dependencies

**Depends on:** nothing beyond Docker and the external `forge-net` network.

**Depended on by:**

- **scoped-mcp** (`registry_db.py`, needs the `[postgres]` extra / `asyncpg`). It writes
  `hitl_approvals` when a gated call is rejected and updates the row when the approval is
  resolved. It also upserts `sessions` and links `session_tasks` using the run id from the
  `X-Forge-Run-Id` header, which task-dispatcher mints as `FORGE_RUN_ID` for each launch.
  Interactive sessions have no run id, so they register nothing.
- **matrix-dispatcher** (`registry.py`, `hitl.py`). It upserts `sessions` for each turn,
  and its resume-on-approval loop reads `hitl_approvals.state` to restart a session once an
  approval lands.

**Fail-open everywhere.** Both consumers treat the registry as best-effort. Any of these
turns every registry call into a logged no-op:

- `AGENT_REGISTRY_DSN` is unset
- `asyncpg` is missing
- the database is down
- a query fails

The HITL decision itself is unaffected. If agent-postgres is down, approvals still work but
are not recorded, and matrix-dispatcher falls back to manual retry instead of resuming the
session automatically.

## Operations

```bash
# Health (the compose healthcheck runs pg_isready)
docker ps --filter name=agent-postgres --format '{{.Status}}'
docker exec agent-postgres pg_isready -U agent_platform

# Logs
docker logs --tail 100 agent-postgres

# Restart
cd ~/docker/agent-platform && docker compose restart agent-postgres

# Upgrade the image without touching agent-dragonfly
cd ~/docker/agent-platform && docker compose pull agent-postgres && docker compose up -d --no-deps agent-postgres

# Inspect the schema (read-only)
docker exec agent-postgres psql -U agent_platform -d agent_platform -c '\dt'
docker exec agent-postgres psql -U agent_platform -d agent_platform \
  -c "SELECT state, count(*) FROM hitl_approvals GROUP BY state"
```

**Is attribution actually recording?** You can't tell from the database alone, because a
fail-open writer that has stopped working leaves no error behind. Check scoped-mcp's
`scoped_mcp_status` output instead. Its `session_registry.state` field is one of:

| State | Meaning |
|-------|---------|
| `disabled` | No DSN configured. Off by design |
| `uninitialised` | Configured, but no writer has run yet in this process. The pool is built lazily on first use |
| `unavailable` | Configured, but the pool could not be built. **Approvals are not being recorded** |
| `recording` | Pool is live and writes are landing |

### Container hardening

- Runs as `user: "1000:1000"` (matches the host operator uid). The data dir is owned by
  that user
- `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`
- Published on localhost only. Other containers on `forge-net` can still reach it on 5432,
  so password auth is the only protection there

### Backup

The data dir is under the appdata root, so [docker-stack-backup](../foundation/docker-stack-backup.md)
captures it with the rest of the stack (stopped, snapshotted, archived; see
[appdata-layout.md](../../operations/appdata-layout.md)).
That is a file-level copy. For a consistent snapshot, take a `pg_dump` first, or stop the
container for the duration of the backup.

### Upgrades

Minor version bumps (17.x → 17.y) only need the image pulled and the container recreated.
Check the PostgreSQL release notes for migration caveats first. A major-version jump needs
`pg_upgrade` or a dump and restore. The `postgres` image does not upgrade an existing data
dir by itself.

## scoped-mcp Integration

No agent can query agent-postgres through MCP. No scoped-mcp module exposes it as a tool
surface, so agents cannot read or write the registry directly. scoped-mcp uses it only
internally, as the backend for HITL audit and session attribution, through the
`agent_registry` role. Whether that is enabled for an agent depends on whether the agent's
scoped-mcp process has `AGENT_REGISTRY_DSN` in its environment.

The audit trail can be trusted for two reasons:

- `agent_id` always comes from the scoped-mcp process's own manifest-pinned `AGENT_ID`,
  never from a request header.
- `upsert_session` refuses to take over a session row that belongs to a different agent.

So the only thing a header can supply is the run id, and a run id that does not validate is
stored as `NULL`.

## Related Docs

- [dragonfly.md](dragonfly.md): sibling in the same stack, holds the fail-closed HITL gate token
- [scoped-mcp.md](scoped-mcp.md): HITL gate and session attribution
- [matrix-dispatcher.md](matrix-dispatcher.md): resume-on-approval consumer
- [task-dispatcher.md](task-dispatcher.md): mints the `FORGE_RUN_ID` run id
