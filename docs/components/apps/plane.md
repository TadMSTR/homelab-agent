# Plane

Self-hosted project and issue tracking (makeplane/plane) on forge. Twelve-container Docker
stack — Next.js frontends, a Django REST backend, Celery workers, and its own PostgreSQL,
Valkey, RabbitMQ, and MinIO datastores. Forge agents file and query work items through
[plane-mcp](../mcp-servers/plane-mcp.md); GitHub/CI events flow in via the
`plane-webhook-listener` PM2 service.

---

## Architecture

| Container | Image | Purpose |
|-----------|-------|---------|
| `plane-web` | `makeplane/plane-frontend:stable` | Main web UI (Next.js) |
| `plane-space` | `makeplane/plane-space:stable` | Public/shared views |
| `plane-admin` | `makeplane/plane-admin:stable` | Instance admin console |
| `plane-live` | `makeplane/plane-live:stable` | Real-time collaboration (WebSocket) |
| `plane-api` | `makeplane/plane-backend:stable` | Django REST API (gunicorn) |
| `plane-worker` | `makeplane/plane-backend:stable` | Celery async worker |
| `plane-beat` | `makeplane/plane-backend:stable` | Celery beat scheduler |
| `plane-migrator` | `makeplane/plane-backend:stable` | One-shot DB migration job |
| `plane-db` | `postgres:16-alpine` | Primary database |
| `plane-valkey` | `valkey/valkey:8-alpine` | Cache / Celery result backend |
| `plane-rabbitmq` | `rabbitmq:4-alpine` | Celery broker |
| `plane-minio` | `minio/minio` | S3-compatible object storage (attachments) |

All backend images are pinned by digest in the compose file.

---

## Endpoints

| URL / bind | Purpose | Auth |
|------------|---------|------|
| `https://plane.helmforge.me` | Main web UI | Plane login |
| `127.0.0.1:3007` → `plane-api:8000` | REST API (used by plane-mcp) | API token |
| `127.0.0.1:9203` → `plane-minio:9000` | MinIO S3 API | MinIO credentials |
| `127.0.0.1:9204` → `plane-minio:9090` | MinIO console | MinIO credentials |

`plane.helmforge.me` is proxied by SWAG. Plane uses its own account/login system (no
Authentik forward auth). The API is the single loopback port other forge services consume.

---

## Networks

| Network | Members |
|---------|---------|
| `plane-internal` | All 12 containers — isolated stack mesh |
| `forge-net` | Frontends (`plane-web`, `plane-space`, `plane-admin`, `plane-live`) + `plane-api` — SWAG access |
| `grafana-datasources` | `plane-db`, `plane-valkey` — Grafana/observability read access |

The datastores (`plane-db`, `plane-valkey`, `plane-rabbitmq`, `plane-minio`) are not on
`forge-net`; only the web tier and API are proxied.

---

## Configuration

- Stack directory: `~/docker/plane/`
- Secrets in `~/docker/plane/.env`: `WEB_URL`, `CORS_ALLOWED_ORIGINS`, PostgreSQL
  (`POSTGRES_USER`/`POSTGRES_DB` + password), `RABBITMQ_USER`, `MINIO_ROOT_USER`, and the
  Valkey/Django secret keys.

---

## Dependencies

| Depends on | Why |
|------------|-----|
| `plane-db`, `plane-valkey`, `plane-rabbitmq`, `plane-minio` | Persistence, cache, broker, object store |
| `plane-migrator` | Must complete before API/workers start |
| SWAG + `forge-net` | TLS termination and subdomain routing |

| Depended on by | How |
|----------------|-----|
| [plane-mcp](../mcp-servers/plane-mcp.md) | Wraps the API at `127.0.0.1:3007` for agents |
| `plane-webhook-listener` (PM2) | Receives GitHub/CI webhooks, creates work items |

---

## Operations

### Restart

```bash
cd ~/docker/plane && docker compose down && docker compose up -d
```

The `plane-migrator` container runs migrations on startup and then exits — an `Exited (0)`
status for it is normal.

### Health check

```bash
docker ps --filter name=plane --format 'table {{.Names}}\t{{.Status}}'
curl -s http://127.0.0.1:3007/api/instances/ | python3 -m json.tool
docker exec plane-db pg_isready -U "$POSTGRES_USER"
```

### Logs

```bash
docker logs plane-api --tail 50
cd ~/docker/plane && docker compose logs --tail=50
```

---

## Related docs

- [plane-mcp](../mcp-servers/plane-mcp.md) — MCP wrapper over the Plane API
- `host-forge/plane-projects.md` — project ID / identifier reference
- `host-forge/plane-labels.md` — label UUID reference
