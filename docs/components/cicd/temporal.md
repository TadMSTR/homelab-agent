# Temporal

Durable workflow execution engine for forge build pipelines. Runs as a Docker stack with PostgreSQL backend, gRPC API on localhost, and a web UI behind Authentik forward auth.

---

## Architecture

| Component | Image | Purpose |
|-----------|-------|---------|
| `temporal` | `temporalio/server:1.30.2` | Workflow server, gRPC frontend |
| `temporal-postgresql` | `postgres:16` | Persistence backend (2 databases: `temporal`, `temporal_visibility`) |
| `temporal-ui` | `temporalio/ui:2.48.1` | Web dashboard |
| `temporal-admin-tools` | `temporalio/admin-tools:1.30.2` | One-shot schema init |
| `temporal-create-namespace` | `temporalio/admin-tools:1.30.2` | One-shot `default` namespace creation |

---

## Endpoints

| Endpoint | Bind | Purpose |
|----------|------|---------|
| `127.0.0.1:7233` | gRPC | Temporal frontend — workers and clients connect here |
| `temporal.helmforge.me` | HTTPS | Web UI via SWAG (Authentik forward auth) |

The gRPC port is localhost-only. External access is through the UI only, gated by Authentik ProxyProvider.

---

## Configuration

### Docker stack

- Stack directory: `~/docker/temporal/`
- Appdata: `/opt/appdata/temporal/` (`postgres/` data, `tls/` certificates)
- Network: internal `temporal-network` (bridge) + external `forge-net` (UI exposure to SWAG)

### mTLS

Mutual TLS is enforced on the frontend (`requireClientAuth: true`). All clients (workers, admin tools, UI) must present certificates.

- TLS files mounted from `~/docker/temporal/tls/` (ca.crt, server.crt, server.key)
- Worker fetches client certs from Vault AppRole at `secret/data/temporal/worker`

### Custom entrypoint

The server uses a custom entrypoint script (`scripts/temporal-entrypoint.sh`) that substitutes `__POSTGRES_PASSWORD__` and `__BROADCAST_ADDRESS__` placeholders in the config template at startup.

### SWAG proxy

Config: `/opt/appdata/swag/nginx/proxy-confs/temporal.subdomain.conf`
- Routes to `temporal-ui:8080` on `forge-net`
- CORS origin: `https://temporal.helmforge.me`

---

## Dependencies

| Depends on | Why |
|------------|-----|
| PostgreSQL 16 (in-stack) | Workflow persistence and visibility |
| Vault | mTLS certificate distribution via AppRole |
| SWAG | TLS termination and reverse proxy for UI |
| Authentik | Forward auth on `temporal.helmforge.me` |

| Depends on Temporal | Why |
|---------------------|-----|
| `temporal-build-worker` (PM2) | Processes build workflow task queue |
| `task-dispatcher.py` (PM2) | Routes `task_type: workflow` tasks to Temporal |

---

## Operations

### Restart

```bash
cd ~/docker/temporal && docker compose down && docker compose up -d
```

### Health check

```bash
# PostgreSQL
docker exec temporal-postgresql pg_isready -U temporal

# Server — check via worker connectivity or UI
curl -s https://temporal.helmforge.me  # (requires Authentik session)
```

### Logs

```bash
docker logs temporal          # server
docker logs temporal-ui       # UI
docker logs temporal-postgresql  # database
```

### Upgrade safety

The stack includes `scripts/check-temporal-template.sh` which diffs the in-use config template against the upstream embedded template — run this before upgrading the server image.

---

## Security

- All containers run with `cap_drop: ALL` and `no-new-privileges: true`
- Memory limits enforced (server: 1GB, PostgreSQL: 512MB)
- mTLS required on frontend — plaintext gRPC rejected
- PostgreSQL credentials injected at runtime via entrypoint substitution
- gRPC bound to `127.0.0.1` only — no external network exposure
- Audit references: `temporal-mtls-2026-06` (M-01/M-02/M-03, L-01/L-02 resolved)

---

## scoped-mcp integration

No direct MCP server for Temporal. Agents interact with Temporal indirectly:
- **task-dispatcher** routes `task_type: workflow` tasks via `temporal-workflow-start.sh`
- **temporal-build-worker** writes task YAMLs to `~/.claude/task-queue/` for agent pickup
- Agents signal completion via `complete_activity.py` with mTLS credentials from Vault
