# Prometheus

Prometheus scrapes metrics from Grafana ecosystem components on forge. It runs inside the observability stack on the `forge-monitoring` network with no host port exposure — only other containers on the same network can query it.

- **Image:** `prom/prometheus:latest`
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Appdata:** `/opt/appdata/observability/prometheus/`
- **Network:** `forge-monitoring` (internal only)
- **Port:** 9090 (container-internal, not host-bound)
- **Retention:** 30 days

## Configuration

Config file: `/opt/appdata/observability/prometheus/prometheus.yml` (mounted read-only).

**Global settings:**
- `scrape_interval: 30s`
- `evaluation_interval: 30s`

**Scrape targets:**

| Job | Target | What it collects |
|-----|--------|-----------------|
| `prometheus` | `localhost:9090` | Self-monitoring |
| `grafana` | `grafana:3000` | Grafana internal metrics |
| `alloy` | `alloy:12345` | Grafana Alloy metrics |

No alerting rules, remote_write, or recording rules are configured. Prometheus serves as the metrics backend for Grafana ecosystem components only — host-level infrastructure metrics are handled by Telegraf → InfluxDB.

## Storage

Data directory: `/opt/appdata/observability/prometheus/data` (mounted read-write). TSDB retention is 30 days.

## Dependencies

- **Grafana** — queries Prometheus as a data source
- **Alloy** — scraped for pipeline metrics
- Requires `extra_hosts: host.docker.internal:host-gateway` for host-bound scrape targets (currently unused)

## Operations

**Restart:** Prometheus restarts with the observability stack:
```bash
docker compose -f ~/docker/observability/docker-compose.yml restart prometheus
```

**Check targets:**
Access Prometheus targets page through Grafana's Explore view, or exec into the container:
```bash
docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets | python3 -m json.tool
```

**Reload config** (without restart):
```bash
docker exec prometheus kill -HUP 1
```
