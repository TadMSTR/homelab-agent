# Plane (parked 2026-10-25)

Plane (makeplane/plane) was forge's self-hosted project and issue tracker until the
2026-07-19 move to [Vikunja](vikunja.md). It is **parked, not retired**: the stack is stopped
but kept intact, so it can be started again on demand.

## Why parked

Nothing has used Plane day to day since the Vikunja migration. It is kept rather than deleted
because a later gap-fill may copy across the comments and links that migration dropped, and
the gap-fill tool reads Plane's REST API — so Plane has to stay restartable. Parked under the
`service-retirement-2026-10` build, alongside the retirement of
[plane-mcp](../mcp-servers/plane-mcp.md).

## Parked state

- **Containers stopped, not removed** (`docker compose stop`). Every service has
  `restart: "no"`, so nothing comes back on a reboot or a Docker daemon restart.
- **Data untouched** in the stack's bind mounts (PostgreSQL, MinIO, Valkey, RabbitMQ, logs).
- **Archive copy on the NAS:** a `pg_dump -Fc` of the `plane` database (checked with
  `pg_restore --list`) and a tarball of the MinIO attachment store.
- **SWAG route disabled** by renaming `plane.subdomain.conf` to `plane.subdomain.conf.parked`.
- **No consumers left:** plane-mcp is removed from PM2 and from every scoped-mcp manifest, the
  Plane helper scripts are deleted, and Grafana's Plane Valkey data source and its panel are
  removed. The `plane-webhook-listener` was already replaced by
  [webhook-doorman](../agent/webhook-doorman.md) in 2026-08.
- **Secrets kept:** the Plane API credentials and the gap-fill tool's credentials stay in
  place; the webhook secret was deleted.

## Restarting it for a gap-fill

```bash
cd ~/docker/plane && docker compose start          # containers still exist
mv <swag-proxy-confs>/plane.subdomain.conf.parked <swag-proxy-confs>/plane.subdomain.conf
docker exec swag nginx -t && docker exec swag nginx -s reload
```

Use the compose CLI rather than a stack-management UI that may log the stack's `.env` on
deploy. When the gap-fill is done, run `docker compose stop` and rename the conf back to
`.parked`.

If the containers have been removed in the meantime, `docker compose up -d` recreates them
from the same bind mounts. If the bind mounts are gone too, restore the archived dump with
`pg_restore` into a fresh `plane-db`.

## What it was

A twelve-container stack:

| Container | Purpose |
|-----------|---------|
| `plane-web`, `plane-space`, `plane-admin`, `plane-live` | Next.js frontends (main UI, public views, admin console, real-time collaboration) |
| `plane-api` | Django REST API (gunicorn) |
| `plane-worker`, `plane-beat` | Celery worker and beat scheduler |
| `plane-migrator` | One-shot DB migration job |
| `plane-db` | PostgreSQL 16 |
| `plane-valkey` | Cache / Celery result backend |
| `plane-rabbitmq` | Celery broker |
| `plane-minio` | S3-compatible attachment storage |

The web tier was proxied by SWAG at `plane.example.com` (Plane's own login, no Authentik
forward auth); the REST API was published on a single loopback port for plane-mcp. Only the
frontends and API sat on `forge-net`; the datastores stayed on an isolated `plane-internal`
network.

## Related docs

- [vikunja.md](vikunja.md) — the current issue tracker
- [plane-mcp.md](../mcp-servers/plane-mcp.md) — retired MCP wrapper over the Plane API
