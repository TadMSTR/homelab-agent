# Forge — Observability Stack Build

**Completed:** 2026-05-24
**Snapshots:** pre-observability-stack (in `/.snapshots/`)

## What Was Built

Activated forge's observability stack by replacing the unused InfluxDB 2 instance with
InfluxDB 3 Core and building a complete metrics + logs pipeline around it. Three new
services handle metrics collection (Telegraf), Prometheus-format scraping (Prometheus),
and container log collection (Grafana Alloy, replacing EOL Promtail). Two supporting
services extend Grafana: an Image Renderer with AMD iGPU DRI passthrough, and a Grafana
MCP SSE server registered in the sysadmin agent's scoped-mcp config. All 8 images
SHA-pinned at deploy time.

## Components Deployed

| Service | Image | Purpose |
|---------|-------|---------|
| `influxdb` | `influxdb:3-core` | Metrics time-series store (replaces InfluxDB 2) |
| `telegraf` | `telegraf:latest` | System + Docker metrics → InfluxDB 3 |
| `prometheus` | `prom/prometheus:latest` | Native /metrics scraping, 30-day retention |
| `alloy` | `grafana/alloy:latest` | Container log collection → Loki (Promtail replacement) |
| `grafana-mcp` | `grafana/mcp-grafana:latest` | SSE MCP server for sysadmin agent |
| `renderer` | `grafana/grafana-image-renderer:latest` | Panel PNG export with AMD iGPU acceleration |
| `grafana` | `grafana/grafana:latest` | Dashboards — already deployed, datasources updated |
| `loki` | `grafana/loki:latest` | Log store — already deployed |

All services are on the `forge-monitoring` network. Only `grafana` is also on `forge-net`
(for SWAG proxying).

## Pipeline Architecture

**Metrics:**
```
Telegraf (system/Docker inputs)
    └─→ InfluxDB 3 (outputs.influxdb_v3, db=forge)
Prometheus
    └─→ scrapes /metrics from forge-monitoring containers
```

**Logs:**
```
Alloy (discovery.docker + loki.source.docker)
    └─→ Loki (http://loki:3100/loki/api/v1/push)
```

**Visualization/Access:**
```
Grafana → queries InfluxDB (InfluxQL datasource, port 8181)
        → queries Loki (log datasource)
        → queries Prometheus (port 9090)
Grafana MCP (SSE :8014) → sysadmin agent via scoped-mcp
```

## Key Technical Findings

**InfluxDB 3 write path changed completely from v2:**
The `/api/v1/prom/write` and `/api/v2/write` endpoints do not exist in v3. The correct
path is `/api/v3/write_lp?db=forge`. Auth header changed from `Token <v2-token>` to
`Bearer apiv3_...`. Grafana datasource uses InfluxQL (Flux was removed in v3).

**Telegraf `outputs.influxdb_v3` plugin syntax:**
The field is `urls = ["http://influxdb:8181"]` (an array), not `host = "..."` as in
the older InfluxDB v1/v2 plugins. This plugin was added in Telegraf 1.29+.

**Alloy HTTP binding:**
Alloy's default HTTP listener binds to `127.0.0.1:12345`, which means Prometheus cannot
scrape Alloy's `/metrics` from within Docker. Requires
`--server.http.listen-addr=0.0.0.0:12345` in the container command.

**Docker group in containers (numeric GID):**
Telegraf and Alloy both need the Docker group to read `/var/run/docker.sock`. Containers
don't have the group name in their `/etc/group`, so `group_add: ["docker"]` silently
fails. Must use the numeric GID: `group_add: ["989"]` (forge's docker GID).

**Grafana MCP — Docker image only:**
The `@grafana/mcp-grafana` npm package does not exist. The only distribution is
`grafana/mcp-grafana:latest` Docker image. Running via `npx` or installing globally
will fail.

## Security Audit Results

Security audit returned 3 findings. 2 fixed, 1 accepted.

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | `--web.enable-lifecycle` enables unauthenticated `/-/quit` on Prometheus | Removed flag; use `docker kill -s HUP prometheus` for config reload |
| L1 | Low | Loki + InfluxDB on `forge-net` (unnecessary — all consumers on `forge-monitoring`) | Removed `forge-net` from both network lists |
| L2 | Low | Loki has no write auth | Accepted — single-tenant homelab; revisit during system hardening pass |

**Commits:** `345b68f` (M1 + L1), `49c7fad` (CHANGELOG)

## Related Docs

- [influxdb.md](../components/influxdb.md)
- [telegraf.md](../components/telegraf.md)
- [grafana-alloy.md](../components/grafana-alloy.md)
- [grafana-mcp.md](../components/grafana-mcp.md)
- [grafana-image-renderer.md](../components/grafana-image-renderer.md)
