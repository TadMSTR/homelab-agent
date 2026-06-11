# InfluxDB 3 Core

InfluxDB 3 Core is the time-series metrics store for forge's observability stack. It
replaced InfluxDB 2 in May 2026. The v2→v3 migration is a breaking change — write
endpoints, auth format, and client plugins all changed.

- **Version:** v3.9.2 (`influxdb:3-core`)
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Appdata:** `/opt/appdata/observability/influxdb3/`
- **Network:** `forge-monitoring` only (removed from `forge-net` post-audit)
- **Port:** `8181` (not 8086 — that was InfluxDB 1/2)

## Breaking Changes from InfluxDB 2

| Area | InfluxDB 2 | InfluxDB 3 |
|------|-----------|-----------|
| Write endpoint | `/api/v2/write?bucket=...` | `/api/v3/write_lp?db=...` |
| Prom remote_write | `/api/v1/prom/write` | **does not exist in v3** |
| Auth header | `Token <v2-token>` | `Bearer apiv3_...` |
| Query language | Flux + InfluxQL | InfluxQL only (Flux removed) |
| Port | 8086 | 8181 |

**Prometheus remote_write is not supported.** Use Telegraf with the `outputs.influxdb_v3`
plugin as the write path for all metrics.

## Write API

```
POST /api/v3/write_lp?db=forge
Authorization: Bearer apiv3_<token>
Content-Type: text/plain

cpu_usage,host=forge value=12.3 1234567890000000000
```

The `INFLUXDB_TOKEN` env var in `forge.env` holds the `apiv3_...` token. Telegraf reads
it via `env_file` and passes it to the `outputs.influxdb_v3` plugin.

## Environment Variables

| Variable | Value | Notes |
|----------|-------|-------|
| `INFLUXDB3_NODE_IDENTIFIER_PREFIX` | `forge` | Required in v3 — container fails to start without it |
| `INFLUXDB3_OBJECT_STORE` | `file` | Local file storage (not S3) |
| `INFLUXDB3_DB_DIR` | `/var/lib/influxdb3` | Mapped to `/opt/appdata/observability/influxdb3/` |
| `INFLUXDB3_HTTP_BIND_ADDR` | `0.0.0.0:8181` | No host port published — forge-monitoring only |

## Grafana Datasource

InfluxDB 3 uses the legacy InfluxQL query path in Grafana. When configuring the datasource:

- **Type:** InfluxDB
- **Query language:** InfluxQL (not Flux — Flux was removed in v3)
- **URL:** `http://influxdb:8181`
- **Auth:** Custom HTTP headers → `Authorization: Bearer apiv3_<token>`
- **Database:** `forge`

## Ownership and Permissions

InfluxDB 3 runs as uid 1500 internally. The appdata directory must be owned by this user:

```bash
sudo chown -R 1500:1500 /opt/appdata/observability/influxdb3/
```

This was a deployment gotcha at initial setup — Grafana and Telegraf run as different
UIDs and do not need access to this directory directly.

## Security

- Not on `forge-net` (removed L1 finding, commit `345b68f`)
- Token stored in `/home/ted/.secrets/forge.env` (chmod 600)
- No host port published — only reachable from `forge-monitoring` containers

## Related Docs

- [telegraf.md](telegraf.md) — writes metrics to InfluxDB 3
- [forge-observability-stack.md](../../phases/forge-observability-stack.md) — build narrative
