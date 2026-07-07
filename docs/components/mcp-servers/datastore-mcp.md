# datastore-mcp

Multi-backend database MCP server. Exposes read-only query, schema-inspection, and
diagnostic tools across 8 database backends (PostgreSQL, ClickHouse, MongoDB, OpenSearch,
InfluxDB, Valkey/Redis, MySQL, SQLite) through a single FastMCP server, so agents can
inspect forge's datastores without per-database clients.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `datastore-mcp` |
| Type | always-on |
| Script | `/opt/venvs/datastore-mcp/bin/datastore-mcp` |
| Interpreter | none |
| Port | `127.0.0.1:8501` (streamable-http) |
| Config | `/opt/appdata/datastore-mcp/config.toml` (chmod 600) |
| Repo | `~/repos/personal/datastore-mcp/` (GitHub: TadMSTR/datastore-mcp) |

## Configuration

The instance list lives in the TOML config, one `[instances.<name>]` block per datastore.
Each block declares a backend `type`, a connection `url`, and optional write flags.

| Env Var | Value | Purpose |
|---------|-------|---------|
| DATASTORE_MCP_CONFIG | `/opt/appdata/datastore-mcp/config.toml` | Instance definitions + credentials |
| LOG_LEVEL | INFO | Logging level |
| OTEL_EXPORTER_OTLP_ENDPOINT | `http://127.0.0.1:4317` | OTLP gRPC trace endpoint (SigNoz) |

A missing config file causes an immediate startup failure — it is not silently ignored.
Forge instances are populated from the stack `.env` files (`~/docker/*/`), all pointed at
`127.0.0.1` loopback ports (authentik-pg, langfuse-pg/ch, patchmon-pg, signoz-ch, etc.).
See `datastore-mcp/docs/forge.md` for the production instance config.

### Instance fields

| Field | Default | Description |
|-------|---------|-------------|
| `type` | required | Backend type (see Tools) |
| `url` | required | Connection URL |
| `allow_write` | `false` | Permit INSERT/UPDATE/DELETE and write commands |
| `allow_ddl` | `false` | Permit CREATE/DROP/ALTER and unclassified statements |
| `user` / `password` | — | ClickHouse credentials |
| `token` / `org` / `bucket` | — | InfluxDB credentials + default bucket |

## Tools

Seven core tools apply to every backend; each backend adds diagnostic extras.

| Tool | Description |
|------|-------------|
| `list_instances` | Configured instances with type and write flags |
| `health_check` | Status, version, uptime for one instance |
| `query` | Run a read query (SQL / JSON / Redis command / Flux per backend) |
| `schema_inspect` | Table/collection list or column detail |
| `slow_queries` | Recent slow queries (empty if unsupported) |
| `db_stats` | Size, counts, cache ratios |
| `connections` | Active sessions and wait states |

Backend-specific extras include `pg_stat_activity`/`pg_locks`/`bloat_estimate`
(PostgreSQL), `ch_query_log`/`ch_parts_info` (ClickHouse), `mongo_current_op`
(MongoDB), `os_cluster_health` (OpenSearch), `valkey_slow_log` (Valkey), and
`mysql_processlist` (MySQL). See the repo `README.md` / `AGENTS.md` for the full list.

## Security model

All backends default to read-only; write access requires explicit per-instance opt-in.

- **SQL backends** — every statement is parsed by `sqlglot` before execution. `SELECT` is
  always allowed; writes need `allow_write`; DDL and unclassified statements need
  `allow_ddl`. Data-modifying CTEs are detected via AST walk and blocked.
- **Valkey/Redis** — allowlist-gated; dangerous commands (`EVAL`, `CONFIG`, `SCRIPT`,
  `SHUTDOWN`, `ACL`, …) are always blocked regardless of `allow_write`.
- **MongoDB** — `$where`, `$function`, `$accumulator` rejected; no server-side JS.
- **InfluxDB** — Flux `to()` write sinks blocked read-only; bucket names validated.

Forge instances are all configured `allow_write = false`.

## Dependencies

- The datastores it targets (Authentik/Langfuse/Patchmon PostgreSQL, SigNoz/Langfuse
  ClickHouse, etc.), reachable on loopback ports
- SigNoz OTLP collector (`127.0.0.1:4317`) for tracing

## scoped-mcp Access

Not yet registered in the agent scoped-mcp manifests. When wired, expose the read-only
core tools to sysadmin/developer; keep any `allow_write` instances out of agent reach.

## Operations

```bash
# Status
pm2 show datastore-mcp

# Logs
pm2 logs datastore-mcp --lines 30

# Restart (picks up config.toml changes)
pm2 restart datastore-mcp
```

## Related Docs

- [datastore-mcp README](https://github.com/TadMSTR/datastore-mcp) — full tool reference
- `datastore-mcp/docs/forge.md` — forge production instance config
