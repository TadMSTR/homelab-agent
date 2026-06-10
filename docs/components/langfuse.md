# Langfuse

Langfuse is an open-source LLM engineering platform — traces, evaluations, prompt management, and metrics for AI applications. On forge it serves as the primary observability layer for Helm agent pipelines, capturing LLM spans, token usage, and evaluation results from any service that instruments with an OpenTelemetry-compatible SDK.

- **Version:** 3.167.4
- **URL:** `https://langfuse.helmforge.me`
- **Compose:** `~/docker/langfuse/docker-compose.yml`
- **Appdata:** `/opt/appdata/langfuse/`
- **Network:** `langfuse-internal` (isolated) + `forge-net` (langfuse-web only)
- **SWAG proxy:** `langfuse.helmforge.me` → `langfuse-web:3000`

## Network Topology

![Analytics stack network topology](../diagrams/analytics-stack-topology.drawio.svg)

*Langfuse stack (green) and SigNoz stack (purple) on forge, with Alloy telemetry forwarding from claudebox. Dashed lines indicate containers that are members of both their internal network and forge-net.*

## Stack

Six containers, all on an isolated `langfuse-internal` network. Only `langfuse-web` is also on `forge-net` for SWAG access.

| Container | Image | Role |
|-----------|-------|------|
| `langfuse-web` | `langfuse/langfuse:3.167.4` | Web UI and API — port 3000 |
| `langfuse-worker` | `langfuse/langfuse-worker:3.167.4` | Background processing (async event ingestion, evals) |
| `langfuse-db` | `postgres:16-alpine` | Primary datastore — projects, users, prompts, evals |
| `langfuse-clickhouse` | `clickhouse/clickhouse-server:24.12-alpine` | Time-series store — traces, observations, scores |
| `langfuse-dragonfly` | `docker.dragonflydb.io/dragonflydb/dragonfly:v1.37.2` | Queue/cache (Redis-compatible) |
| `langfuse-minio` | `cgr.dev/chainguard/minio` | S3 event storage — blob events and media uploads |

## Startup Order

`langfuse-worker` and `langfuse-web` both depend on `langfuse-db`, `langfuse-clickhouse`, and `langfuse-minio` passing healthchecks. Dragonfly has no healthcheck but is lightweight. On a cold start, expect 30–60s before the web UI is reachable.

## Appdata Layout

```
/opt/appdata/langfuse/
├── clickhouse/
│   ├── data/         → /var/lib/clickhouse
│   └── logs/         → /var/log/clickhouse-server
├── dragonfly/        → /data (Dragonfly RDB snapshots)
├── minio/            → /data (MinIO object storage)
└── postgres/         → /var/lib/postgresql/data
```

## Networking

Two separate Docker networks:

- **`langfuse-internal`** — dedicated isolated network for all Langfuse containers. Internal DNS resolves `langfuse-clickhouse`, `langfuse-db`, `langfuse-dragonfly`, `langfuse-minio`. No other forge services can reach these directly.
- **`forge-net`** — shared forge network. Only `langfuse-web` is attached here, so SWAG can proxy to it. `langfuse-worker` does not need external access.

## Environment Variables

All secrets in `~/docker/langfuse/.env` (600). Key variables:

| Variable | Notes |
|----------|-------|
| `LANGFUSE_SALT` | Random hex string — password hashing salt. Never change after first deploy. |
| `LANGFUSE_ENCRYPTION_KEY` | 64-char hex — encrypts secrets at rest. Never change after first deploy. |
| `LANGFUSE_NEXTAUTH_SECRET` | NextAuth session secret. |
| `CLICKHOUSE_USER` / `CLICKHOUSE_PASSWORD` | ClickHouse auth. User defaults to `clickhouse`. |
| `LANGFUSE_DB_USER` / `LANGFUSE_DB_PASSWORD` | Postgres auth. User defaults to `langfuse`. |
| `LANGFUSE_DRAGONFLY_PASSWORD` | Passed via `DFLY_requirepass` env var (not `--requirepass` CLI arg). |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | MinIO admin and S3 access key — same credentials used for both. |
| `AUTHENTIK_LANGFUSE_CLIENT_ID` / `AUTHENTIK_LANGFUSE_CLIENT_SECRET` | Authentik OIDC provider credentials. |

## Authentik SSO

Langfuse is wired to Authentik via OIDC. Key env vars in `langfuse-web`:

```yaml
AUTH_CUSTOM_CLIENT_ID: ${AUTHENTIK_LANGFUSE_CLIENT_ID}
AUTH_CUSTOM_CLIENT_SECRET: ${AUTHENTIK_LANGFUSE_CLIENT_SECRET}
AUTH_CUSTOM_ISSUER: https://auth.helmforge.me/application/o/lang-fuse   # no trailing slash
AUTH_CUSTOM_NAME: Authentik
AUTH_CUSTOM_SCOPE: "openid email profile"
AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING: "true"   # Langfuse-specific var
HOSTNAME: "0.0.0.0"                          # required for SWAG → langfuse-web connectivity
```

```yaml
extra_hosts:
  - "auth.helmforge.me:172.20.1.5"   # server-side OIDC discovery routes through SWAG
```

**Gotchas that bit deployment:**
- `AUTH_CUSTOM_ISSUER` must **not** have a trailing slash — trailing slash causes a double-slash in the discovery URL, which nginx 301-redirects, breaking the OIDC flow.
- `AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING=true` is the correct var. The standard `AUTH_CUSTOM_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING` does **not** work in this context.
- `HOSTNAME=0.0.0.0` is required. Without it, `langfuse-web` only binds on localhost inside the container, and SWAG (reaching via `forge-net`) gets a connection refused.
- Authentik SSO app slug must be `lang-fuse` (with hyphen) to match the issuer URL path.

## MinIO (S3 Event Storage)

Mandatory since Langfuse ~v3.140+. The worker and web containers both require a working S3 endpoint at startup — if MinIO is unhealthy, the Langfuse containers won't start.

MinIO bucket `langfuse` is auto-created at container startup via the entrypoint:
```bash
sh -c 'mkdir -p /data/langfuse && minio server ...'
```

Both worker and web connect to `http://langfuse-minio:9000` using path-style addressing (`LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true`). MinIO console is accessible at `127.0.0.1:9201` (localhost-only, no SWAG proxy).

## ClickHouse Configuration

Single-node deployment (no cluster). Key env vars:

```
CLICKHOUSE_MIGRATION_URL: clickhouse://langfuse-clickhouse:9000   # TCP — must use clickhouse://, not http://
CLICKHOUSE_URL: http://langfuse-clickhouse:8123                   # HTTP for queries
CLICKHOUSE_CLUSTER_ENABLED: "false"
```

The `CLICKHOUSE_MIGRATION_URL` **must** use the `clickhouse://` scheme (TCP port 9000). Using `http://` will cause migration failures at startup.

Retention TTLs applied post-deploy (see [Security](#security)):
```sql
ALTER TABLE traces MODIFY TTL toDate(created_at) + INTERVAL 90 DAY;
ALTER TABLE observations MODIFY TTL toDate(start_time) + INTERVAL 90 DAY;
ALTER TABLE scores MODIFY TTL toDate(created_at) + INTERVAL 90 DAY;
ALTER TABLE event_log MODIFY TTL toDate(created_at) + INTERVAL 90 DAY;
```

## Dragonfly (Queue/Cache)

Langfuse uses Dragonfly as a Redis-compatible queue for async event processing. Configuration:

```yaml
command: >
  --maxmemory 512mb
  --proactor_threads=2
environment:
  DFLY_requirepass: ${LANGFUSE_DRAGONFLY_PASSWORD}
```

**512MB / 2 threads** — forge-wide Dragonfly constraint: minimum 256MB maxmemory per proactor thread. At 512MB, 2 threads is the maximum safe configuration. This is distinct from the standalone Dragonfly instance (`dragonfly` container at `127.0.0.1:6380`) used by Helm agents — that one gets 2GB / 4 threads.

Password is set via `DFLY_requirepass` environment variable, not `--requirepass` CLI arg. The CLI arg approach embeds the plaintext password in `docker inspect` output.

## Operator First-Login Steps

On a fresh deploy:
1. Navigate to `https://langfuse.helmforge.me`
2. Click "Sign up" — create the admin account (email + password, before wiring Authentik)
3. Create organization: `Helm`
4. Create default project: `helm-default`
5. After confirming the app works: wire Authentik SSO (populate `AUTH_CUSTOM_*` vars, restart stack)
6. Sign in via Authentik to link accounts

## Agent Project: forge-agents

The `forge-agents` project is the Langfuse project used for LLM observability across operator agents (Dockhand, Hister, CloudCLI, and any future agent stack on forge). It is a separate project from `helm-default` so agent traces are scoped and keys can be rotated independently.

### LANGFUSE_INIT_* Workaround

The `LANGFUSE_INIT_ORG_NAME`, `LANGFUSE_INIT_PROJECT_NAME`, and related env vars documented in the Langfuse README do **not** reliably propagate from a `.env` file into the running container via `docker compose`. These vars are used for YAML variable substitution at parse time, not injected as container environment — a `docker compose restart` or `up -d` does not re-read them. If present in `.env`, they are silently ignored by the container.

**Workaround:** Seed the project directly via Postgres INSERT into the `langfuse` database:

```bash
# Connect to the langfuse-db container
docker exec -it langfuse-db psql -U langfuse -d langfuse

# Insert the project (use a UUID for id; get org id from the Organization table)
INSERT INTO "Project" (id, name, "organizationId", "createdAt", "updatedAt")
VALUES ('forge-agents-proj-001', 'forge-agents', '<org-id>', NOW(), NOW());

# Insert the API key pair (public key plain, secret key SHA256-hashed)
INSERT INTO "ApiKey" ("id", "projectId", "createdAt", "publicKey", "hashedSecretKey", "fastHashedSecretKey", "displaySecretKey")
VALUES (gen_random_uuid(), 'forge-agents-proj-001', NOW(), 'pk-lf-<value>', '<sha256-of-secret>', '<fast-hash>', 'sk-lf-***');
```

After seeding, verify the project appears in the Langfuse UI under the `helm-default` organization before distributing keys to agents.

### Secrets Isolation

Agent API keys are stored in `/opt/secrets/langfuse.env` (chmod 600, owned by ted):

```bash
LANGFUSE_PUBLIC_KEY=pk-lf-<value>
LANGFUSE_SECRET_KEY=sk-lf-<value>
LANGFUSE_HOST=https://langfuse.helmforge.me
```

Per-agent `.env` files at `/opt/agents/<agent>/.env` are written by `~/scripts/write-agent-envs.sh`, which sources `/opt/secrets/langfuse.env` at runtime — the script itself contains no plaintext keys. Each agent reads its own `.env` at startup to pick up the three Langfuse vars.

This isolation means:
- The plaintext key lives in exactly one place (`/opt/secrets/langfuse.env`)
- Rotating keys requires updating that file and re-running `write-agent-envs.sh` — no agent compose files or scripts need editing
- Agent `.env` files are chmod 600 and not committed to any Gitea repo

## Security

Post-deploy security state from audit 2026-04-15:

| Finding | Status |
|---------|--------|
| Dragonfly password in docker inspect (L1) | ✓ fixed — moved to `DFLY_requirepass` env var |
| Authentik SSO not wired (L4) | ✓ fixed — Authentik OIDC provider `lang-fuse` wired |
| ClickHouse retention not configured (L5) | ✓ fixed — 90-day TTL on traces/observations/scores/event_log |
| Volumes not backed up (L6) | ✓ fixed — covered by `/home/ted/scripts/docker-stack-backup.sh` (2 AM daily) |
| No Authelia layer on SWAG proxy (M1) | deferred — Langfuse has native Authentik SSO; no Authelia gate currently |
| Agent keys hardcoded in write-agent-envs.sh (M4, 2026-05-16) | ✓ fixed — moved to `/opt/secrets/langfuse.env` (chmod 600); script sources at runtime |

SWAG proxy passes through to `langfuse-web:3000`. Authentik SSO is the auth layer. `.env` is `600 ted:ted`.

## Backup

Covered by `~/scripts/docker-stack-backup.sh` on forge. Stop → `sudo tar` → restart. Backup destination: `/mnt/atlas/forge/backups/docker-backups/`. Schedule: 2 AM daily.

Priority order if restoring selectively:
1. `postgres/` — project/user/eval data (critical)
2. `minio/` — trace event blobs (critical)
3. `clickhouse/` — time-series traces (large, reconstructable from re-ingestion)
4. `dragonfly/` — hot cache (skip — TTL-bound, rebuilds on next event)

## Related Docs

- [dragonfly.md](dragonfly.md) — standalone Dragonfly for Helm agents (different instance, 2GB/4 threads)
- [phase-analytics-stack.md](../phases/phase-analytics-stack.md) — build narrative for this stack
- [signoz.md](signoz.md) — companion APM/observability stack
