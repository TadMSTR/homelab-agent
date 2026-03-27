# Plane

Plane is a self-hosted project management platform. In this stack it serves as the visual tracking board for the Helm platform build — a large architecture project that needs dependency-aware issue tracking, module grouping, cycle-based sprints, and Gantt timeline views. It runs as an 11-container Docker stack behind SWAG with Authelia SSO.

An MCP server (`plane-mcp-server`) provides 55+ tools for reading and writing workspace data from Claude Code sessions, giving agents direct access to project state without manual UI interaction.

## Why Plane

The Helm platform architecture has 35+ sections covering infrastructure, agents, catalogs, and platform services. Tracking this in markdown files or memory notes doesn't scale — you need a real project board with dependencies, groupings, and timeline visualization to see what blocks what and plan build sprints.

Plane was chosen over:
- **Vikunja** — too flat; no module/epic grouping or dependency tracking
- **Leantime** — weaker developer tooling, less active development
- **OpenProject** — heavier weight, dated UI, less Docker-friendly
- **GitHub Projects** — limited dependency management, no self-hosted option

Plane's module and cycle system maps directly to the Helm architecture: each architectural layer becomes a module, issues within modules represent build tasks, and cycles track sprint-style build phases.

## How It Works

The stack runs 11 containers across two Docker networks: an internal `plane` network for inter-service communication and the shared `claudebox-net` for SWAG proxy access.

### Containers

| Container | Image | Role |
|-----------|-------|------|
| plane-web | makeplane/plane-frontend:stable | Next.js frontend |
| plane-admin | makeplane/plane-admin:stable | Admin panel (god-mode) |
| plane-space | makeplane/plane-space:stable | Public/shared project spaces |
| plane-live | makeplane/plane-live:stable | WebSocket server for live collaboration |
| plane-api | makeplane/plane-backend:stable | Django REST API |
| plane-worker | makeplane/plane-backend:stable | Celery background worker |
| plane-beat-worker | makeplane/plane-backend:stable | Celery beat scheduler |
| plane-db | postgres:15.7-alpine | PostgreSQL database |
| plane-redis | valkey/valkey:7.2.11-alpine | Cache and sessions |
| plane-mq | rabbitmq:3.13.6-management-alpine | Celery task broker |
| plane-minio | minio/minio:latest | S3-compatible object storage (uploads) |

### Ports

- `127.0.0.1:8180` → plane-api:8000 — localhost-only API access for MCP and internal tooling (bypasses Authelia)
- All other access via SWAG at `plane.yourdomain` (Authelia-protected)

### Storage

Persistent data uses bind mounts under `/opt/appdata/plane/`, consistent with every other stack on claudebox:

| Host Path | Purpose |
|-----------|---------|
| `/opt/appdata/plane/pgdata` | PostgreSQL database |
| `/opt/appdata/plane/redisdata` | Valkey cache |
| `/opt/appdata/plane/uploads` | MinIO object storage (file attachments) |
| `/opt/appdata/plane/rabbitmq_data` | RabbitMQ persistence |
| `/opt/appdata/plane/logs` | Application logs (API, worker, beat-worker, migrator) |

## SWAG Proxy Configuration

The proxy conf (`plane.subdomain.conf`) routes different URL paths to different containers. This is more complex than most services because Plane has multiple frontend apps and a separate API.

| Path | Target | Notes |
|------|--------|-------|
| `/api/*` | plane-api:8000 | Django REST backend |
| `/auth/*` | plane-api:8000 | Authentication endpoints (Django) |
| `/god-mode/*` | plane-admin:3000 | Admin panel |
| `/spaces/*` | plane-space:3000 | Shared project spaces |
| `/live/*` | plane-live:3000 | WebSocket (Upgrade/Connection headers preserved) |
| `/uploads/*` | plane-minio:9000 | S3 file gateway |
| `/` | plane-web:3000 | Main Next.js frontend (catch-all) |

Authelia is enabled on all routes. The localhost API port (8180) exists specifically for internal callers (MCP server, future agents) that need to bypass SSO.

Client body size is set to 5MB, matching Plane's `FILE_SIZE_LIMIT`.

## MCP Integration

The `plane-mcp-server` package (installed via `uvx`) provides 55+ tools covering the full Plane API surface: projects, work items, cycles, modules, epics, initiatives, labels, members, custom properties, and search.

| Setting | Value |
|---------|-------|
| Package | `plane-mcp-server` (PyPI) |
| Transport | stdio (`uvx plane-mcp-server stdio`) |
| API endpoint | `http://localhost:8180` (internal, bypasses Authelia) |
| Workspace slug | `helm` |

The MCP server connects to the localhost API port, not the SWAG proxy. This avoids SSO session management and keeps MCP traffic internal. The API key is generated in Plane's workspace settings UI.

## Configuration

**Docker Compose:** `~/docker/plane/docker-compose.yml`

**Environment (`.env`):**

| Variable | Purpose |
|----------|---------|
| `SECRET_KEY` | Django secret key (64-byte hex) — encrypts sessions and tokens |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Valkey connection string |
| `RABBITMQ_*` | RabbitMQ credentials and vhost |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | MinIO credentials for S3 storage |
| `WEB_URL` | Public URL (`https://plane.yourdomain`) |
| `CORS_ALLOWED_ORIGINS` / `CSRF_TRUSTED_ORIGINS` | Must match WEB_URL |
| `FILE_SIZE_LIMIT` | Upload limit in MB (default 5) |
| `GUNICORN_WORKERS` | API worker count (1 for homelab scale) |
| `API_KEY_RATE_LIMIT` | Requests per minute (60) |

Images are pulled from Docker Hub (`makeplane/`), not Plane's own registry at `artifacts.plane.so` — Pi-hole DNS blocks that domain.

## Integration Points

**SWAG + Authelia.** All browser access goes through the SWAG proxy with Authelia authentication. The multi-path routing is the most complex proxy conf in the stack but follows the same pattern as every other service.

**MCP server.** Claude Code agents can read project state (issues, modules, cycles, dependencies) and write updates (create issues, move items between cycles, update status) directly from conversation. This is the primary integration point for Phase 2 (board population) and Phase 3 (automated agent).

**Backup and restore.** The compose file, `.env` (with secrets), and SWAG proxy conf are all backed up by `backup-claude.sh` to NFS. The deploy script restores all three on rebuild. Appdata at `/opt/appdata/plane/` is covered by the docker-stack-backup script like every other stack. `SECRET_KEY` is the critical secret — without it, sessions and encrypted data become unreadable after restore.

## Build Plan

Plane is deployed in three phases:

**Phase 1 (complete):** Docker stack deployment, SWAG proxy, MCP registration, backup/deploy integration. Everything documented here.

**Phase 2 (pending — weekday brainstorming):** Populate the Helm project board. Create workspace, define 13 modules mapping to architecture layers, break the architecture doc into actionable issues, map dependencies, define the first build cycle.

**Phase 3 (deferred — post-Helm):** Custom webhook agent. FastAPI receiver on PM2, Claude Code SDK integration for agent logic, Plane Agent Run API client for activity posting, OAuth app for @mention capability. Designed for portability to the Helm catalog.

## Gotchas and Lessons Learned

**plane-space reports "unhealthy" but works fine.** The Alpine image doesn't include `curl`, which the Docker healthcheck expects. The service runs normally — it's a cosmetic issue in `docker ps` output. Not worth fixing unless it causes orchestration problems.

**`/auth/*` must route to the API, not the frontend.** Plane's authentication endpoints are Django views served by the API container. If SWAG routes `/auth/*` to the web frontend (the default catch-all), login fails with CSRF errors. The proxy conf has an explicit `/auth/*` block routing to plane-api:8000.

**Docker Hub images, not artifacts.plane.so.** Plane's official compose pulls from `artifacts.plane.so`, but Pi-hole blocks that domain (resolves to 0.0.0.0). The same images are available on Docker Hub as `makeplane/*`. Set `DOCKERHUB_USER=makeplane` and use Docker Hub tags.

**RabbitMQ replaced Redis for task queuing.** Plane moved Celery's broker from Redis to RabbitMQ. Valkey/Redis still handles caching and sessions, but the task queue runs through RabbitMQ. Both are required — don't skip either thinking they're redundant.

**Rate limiting is per-API-key.** The `API_KEY_RATE_LIMIT` (60/min) applies to each API key independently. If the MCP server hits rate limits during bulk operations (Phase 2 board population), either raise the limit or add delays between calls.

## Standalone Value

Plane is useful for any project that outgrows a flat task list. If you self-host Docker stacks and want a project tracker with real dependency management, module grouping, and timeline views, Plane is the lightest weight option in the space. The MCP server integration is specific to this stack, but Plane itself works with any workflow.

## Further Reading

- [Plane documentation](https://docs.plane.so/)
- [Plane self-hosting guide](https://docs.plane.so/docker-compose)
- [plane-mcp-server](https://pypi.org/project/plane-mcp-server/) — MCP server package

---

## Related Docs

- [SWAG](swag.md) — reverse proxy handling the multi-path routing
- [Authelia](authelia.md) — SSO protecting all browser routes
- [claudebox-deploy](claudebox-deploy.md) — deploy script with Plane secrets restore
- [Backups](backups.md) — NFS backup covering compose, secrets, and proxy conf
