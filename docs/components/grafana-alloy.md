# Grafana Alloy

Grafana Alloy is the container log collector for forge, replacing EOL Promtail. It
discovers running Docker containers, tails their logs, and ships them to Loki. On forge,
Alloy handles log collection only — system metrics are handled by Telegraf.

- **Image:** `grafana/alloy:latest` (SHA-pinned in compose)
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Config:** `/opt/appdata/observability/alloy/config.alloy` (mounted `:ro`)
- **Network:** `forge-monitoring`

## Configuration

```alloy
// Log collection only — metrics handled by Telegraf

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.docker.containers.targets
  forward_to = [loki.write.loki.receiver]
  labels = {
    job = "docker",
  }
}

loki.write "loki" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

All container logs flow to Loki with a `job="docker"` label. Container-specific labels
(container name, image) are added automatically by `loki.source.docker`.

## Critical: HTTP Listen Address

Alloy's default HTTP listener binds to `127.0.0.1:12345`. Inside Docker, this means
Prometheus cannot scrape Alloy's `/metrics` endpoint — `127.0.0.1` resolves to the
container's loopback, not the host. The compose command overrides this:

```yaml
command:
  - run
  - /etc/alloy/config.alloy
  - --server.http.listen-addr=0.0.0.0:12345
```

Without this flag, Alloy's own metrics are invisible to Prometheus.

## Docker Group Access

Like Telegraf, Alloy accesses `/var/run/docker.sock` for container discovery and log
reading. The Docker group GID on forge is `989`. Must use numeric GID:

```yaml
group_add:
  - "989"    # docker group — must be numeric
```

## Scope on Forge

Alloy on forge is **log collection only**. Unlike the SigNoz Alloy config on claudebox
(which also exports OTLP telemetry to forge), forge's Alloy is a simple
discovery→collect→push pipeline with no OTEL exporter.

## Related Docs

- [forge-observability-stack.md](../phases/forge-observability-stack.md) — build narrative
- [signoz.md](signoz.md) — claudebox Alloy (different config: OTLP exporter to forge)
