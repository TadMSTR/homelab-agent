# Prometheus

Prometheus scrapes metrics from the observability stack's own components, a handful of platform services, and remote fleet hosts. It runs inside the observability stack on the `forge-monitoring` network with no host port exposure — only other containers on its networks can query it.

- **Image:** `prom/prometheus:v3.15.0`, pinned by digest (`prom/prometheus:v3.15.0@sha256:…`); Renovate proposes bumps
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Appdata:** `/opt/appdata/observability/prometheus/`
- **Networks:** `forge-monitoring` (internal only) and `prometheus-scrape` (an external network that services join only so Prometheus can reach their metrics endpoint)
- **Port:** 9090 (container-internal, not host-bound)
- **Retention:** 30 days
- **Hardening:** `cap_drop: ALL`, `no-new-privileges`, `mem_limit: 768m`

## Configuration

Config file: `/opt/appdata/observability/prometheus/prometheus.yml` (mounted read-only).
Scrape credentials are never inline: jobs that need a Bearer token read it through
`credentials_file` from a `secrets/` directory mounted read-only at `/etc/prometheus/secrets`
(files `0400`, directory `0500`, not tracked in any repo).

**Global settings:**
- `scrape_interval: 30s`
- `evaluation_interval: 30s`

**Scrape targets (12 jobs, verified 2026-10-27; all `up`):**

| Job | Target | Auth | What it collects |
|-----|--------|------|-----------------|
| `prometheus` | `localhost:9090` | none | Self-monitoring |
| `grafana` | `grafana:3000` | none | Grafana internal metrics |
| `alloy` | `alloy:12345` | none | Grafana Alloy pipeline metrics |
| `loki` | `loki:3100` | none | Loki ingest and retention metrics (the Loki alert rules depend on it) |
| `nvidia_gpu` | `nvidia-exporter:9835` (15s) | none | GPU utilisation, memory, temperature |
| `ollama_queue_proxy` | `ollama-queue-proxy:11435` (15s) | Bearer | Ollama queue depth and request metrics |
| `vikunja` | `vikunja:3456`, path `/api/v1/metrics` | none | Vikunja application metrics |
| `webhook_doorman` | `webhook-doorman:8080` | none | Webhook source/sink names and traffic volume (never payloads) |
| `healthchecks` | `healthchecks:8000`, project metrics path (60s) | Bearer (read-only API key) | `hc_check_up` per cron check, feeding the `CronJobDown` alert |
| `docker_stack_backup` | `alloy:12345`, Alloy textfile exporter path (60s) | none | Nightly compose-stack backup results (`dsb_*`) |
| `technitium-<host>` | `<lan-host>:5380`, path `/api/dashboard/metrics/text` | Bearer (view-only user) | DNS server metrics from a fleet host |
| `node-<host>` | `<lan-host>:9100` | none (host firewall admits only the Prometheus host) | node_exporter host metrics from a fleet host |

Two jobs treat their input as untrusted and relabel it at scrape time:

- **`healthchecks`** — the `name` label is a check name any Healthchecks user can write, so any
  value outside the slug charset is replaced with `invalid-check-name`. Grafana's default
  notification template prints labels raw, so this keeps markup out of chat alerts.
- **`docker_stack_backup`** — the textfile directory is writable by the operator account,
  so the job keeps only `dsb_*` and `node_textfile_*` metric names, keeps only known label
  names, forces free-text labels into a safe charset, and deliberately does not set
  `honor_labels` (a file cannot claim another job's identity).

**Alerting:** Prometheus itself has no `rule_files`, recording rules, `alerting:` block or
`remote_write`; its rules API returns no groups. Alerting is Grafana-managed: provisioned
Grafana alert rules query Prometheus as a datasource (for example `PrometheusTargetDown`,
`CronJobDown`, the Loki and backup rules) and route through Grafana contact points. See
[grafana-dashboards.md#alerting](grafana-dashboards.md#alerting).

Host-level infrastructure metrics for the main host are still handled by Telegraf → InfluxDB.

## Storage

Data directory: `/opt/appdata/observability/prometheus/data` (mounted read-write). TSDB retention is 30 days.

## Dependencies

- **Grafana** — queries Prometheus as a data source
- **Alloy** — scraped for pipeline metrics
- **Scraped services** — loki, nvidia-exporter, ollama-queue-proxy, vikunja, webhook-doorman, healthchecks and the fleet hosts above; a target going down fires `PrometheusTargetDown` in Grafana
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
