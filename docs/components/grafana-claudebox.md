# Grafana (claudebox)

Claudebox runs its own local Grafana + InfluxDB stack, separate from the atlas-hosted monitoring stack that covers homelab infrastructure. This one exists solely for AI agent observability — Claude Code session metrics, token usage, estimated costs, and LibreChat activity. Keeping it local avoids mixing agent telemetry into homelab dashboards and means the data pipeline stays entirely on the machine generating the data.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) alongside the other Docker services, and feeds downstream from the [ai-cost-tracking](ai-cost-tracking.md) pipeline in Layer 3.

## Why a Separate Stack

The atlas Grafana + InfluxDB instance handles infrastructure metrics: CPU, RAM, disk, Docker health, network — the kind of data Telegraf and Netdata ship by default. That's homelab monitoring.

Agent observability is a different category. Claude Code session durations, token counts, estimated spend, model breakdown, LibreChat conversation volume — this data is generated locally on claudebox and isn't meaningful in the context of a disk health dashboard. A separate stack keeps concerns separated and makes it easier to build purpose-specific dashboards without cluttering the infrastructure view.

There's also a practical reason: running the full data pipeline locally (Python script → Telegraf → local InfluxDB → local Grafana) avoids sending agent session data across the network to atlas. The data stays on the machine where it was generated.

## Stack

Two containers in a shared Docker Compose file:

```
grafana/grafana:11.6.0    → port 3025 (internal) → grafana.yourdomain
influxdb:2.7              → port 8086 (internal)
```

Port 3025 for Grafana because 3000 is already taken by Dockhand. Port 8086 for InfluxDB has no conflicts. Both bind to `127.0.0.1` — SWAG handles external access.

Both containers live on `claudebox-net`, the shared Docker network used by all local services.

## Prerequisites

- Docker and Compose on the host
- SWAG running with a wildcard certificate for your domain
- An InfluxDB admin token (generated on first run) — stored in the stack `.env` file

## Configuration

The Docker Compose file at `~/docker/grafana/docker-compose.yml`:

```yaml
services:
  grafana:
    image: grafana/grafana:11.6.0
    container_name: grafana
    restart: unless-stopped
    ports:
      - "127.0.0.1:3025:3000"
    environment:
      - GF_SERVER_ROOT_URL=https://grafana.yourdomain
      - GF_SECURITY_ADMIN_PASSWORD=${GF_ADMIN_PASSWORD}
    volumes:
      - /opt/appdata/grafana:/var/lib/grafana
    networks:
      - claudebox-net

  influxdb:
    image: influxdb:2.7
    container_name: influxdb
    restart: unless-stopped
    ports:
      - "127.0.0.1:8086:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_ORG=claudebox
      - DOCKER_INFLUXDB_INIT_BUCKET=claudebox-agent
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUXDB_ADMIN_TOKEN}
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUXDB_ADMIN_PASSWORD}
    volumes:
      - /opt/appdata/influxdb:/var/lib/influxdb2
    networks:
      - claudebox-net

networks:
  claudebox-net:
    external: true
```

The `.env` file in the same directory holds `GF_ADMIN_PASSWORD`, `INFLUXDB_ADMIN_TOKEN`, and `INFLUXDB_ADMIN_PASSWORD`.

**InfluxDB first-run:** The `DOCKER_INFLUXDB_INIT_*` variables only apply on initial startup when the data directory is empty. After that, they're ignored — don't change the token in the env file without also updating it everywhere it's used (Telegraf output config, Grafana datasource, etc.).

**SWAG proxy conf** at `/opt/appdata/swag/nginx/proxy-confs/grafana.subdomain.conf` — standard subdomain config pointing upstream to `127.0.0.1:3025`.

## Integration Points

**Telegraf** is the primary data source. The existing Telegraf instance on claudebox is configured with a second `[[outputs.influxdb_v2]]` block that routes `claude_*` and `librechat_*` measurements to the local InfluxDB. The existing atlas output is unchanged — Telegraf writes infra metrics to atlas and agent metrics to localhost. See [ai-cost-tracking](ai-cost-tracking.md) for the full data pipeline.

**InfluxDB datasource in Grafana:** After standing up the stack, add a datasource in Grafana pointing to `http://influxdb:8086` (container name resolves on the shared network). Org: `claudebox`, bucket: `claudebox-agent`, token: the admin token from the `.env` file.

**SWAG + Authelia:** Like other claudebox services, Grafana is proxied through SWAG with Authelia authentication. The SWAG conf just proxies to `127.0.0.1:3025` — no special handling needed.

## Resource Overhead

Grafana idles at around 50–100MB RAM. InfluxDB varies with write volume — at Telegraf's 5-minute polling rate for agent metrics, expect 200–400MB steady-state. Total overhead is roughly 400–600MB, well within headroom on the K11's 32GB.

## Gotchas and Lessons Learned

**InfluxDB admin token vs. password.** Telegraf and the Grafana datasource both use the admin token, not the password. The community InfluxDB MCP server also targets the OSS v2 API — use the token there too.

**Don't pin InfluxDB at 2.x lightly.** InfluxDB 3.x changes the storage engine and query language substantially. The `claudebox-agent` bucket setup is intentionally pinned at 2.7. If you're building dashboards with Flux queries, check migration docs before bumping the version.

**The atlas Grafana instance is separate.** If you're reading this and already run Grafana on a NAS or secondary host, you don't necessarily need a second instance. The reason this exists as a separate stack is concern separation — agent telemetry vs. infrastructure monitoring. You could absolutely add an `agents` bucket to an existing InfluxDB and point your existing Grafana at it, at the cost of mixed dashboards.

## Standalone Value

The Grafana + InfluxDB stack on its own is just a monitoring platform — it needs data sources. Its value is fully realized through the [ai-cost-tracking](ai-cost-tracking.md) pipeline. You could stand this up without the rest of homelab-agent and use it for whatever time-series data you want to visualize locally, but within this stack it's specifically the display layer for agent observability.

## Related Docs

- [grafana-observability](grafana-observability.md) — Loki, image renderer, and Alloy log shipping added to this stack
- [ai-cost-tracking](ai-cost-tracking.md) — the pipeline that feeds this stack
- [SWAG](swag.md) — reverse proxy handling external access
- [Authelia](authelia.md) — SSO in front of Grafana and other services
