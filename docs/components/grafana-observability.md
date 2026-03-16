# Grafana Observability Stack

The claudebox Grafana stack gained three additions as part of the observability build: a local Loki instance for log storage, a grafana-image-renderer sidecar for dashboard snapshot exports, and a dual-destination Alloy config that ships self-healing system logs locally while continuing to forward everything else to the atlas Loki instance. The result is that claudebox's self-healing agents can log structured output to a local log directory and query it via Grafana — without mixing agent diagnostic logs into the broader homelab Loki instance on atlas.

This doc covers those additions. The base Grafana + InfluxDB stack (agent metrics, cost tracking) is documented in [grafana-claudebox](grafana-claudebox.md).

## Why Local Loki

Atlas already runs Loki for homelab log aggregation — systemd journal, syslog, container logs. That instance is the right place for infrastructure diagnostics. It's not the right place for agent self-healing logs.

Self-healing system logs have different characteristics: they're generated locally, consumed locally (by Grafana dashboards on the same host), and most useful in the context of other agent observability data. Mixing them into atlas Loki isn't wrong, but it means your self-healing log queries have to filter through everything else the homelab ships there. A local instance keeps the data close, keeps query scope tight, and avoids adding load to atlas for data that's only relevant to claudebox.

The practical benefit: a single `{job="self-healing"}` query in Grafana pulls up every log line from every self-healing agent without any cross-host networking involved.

## What Got Added

Three additions to the existing `~/docker/grafana/docker-compose.yml`:

**Loki 3.4.2** — local log aggregation for claudebox self-healing system logs. Runs on `127.0.0.1:3100`. Config at `/opt/appdata/grafana/loki-config/loki-config.yml`.

**grafana-image-renderer** — sidecar service that lets Grafana render dashboard panels as PNG images. Required for alert notification snapshots and any workflow that needs exported panel images. Runs internally on port 8081 with no external exposure; Grafana talks to it over the shared Docker network.

**Alloy dual-destination config** — the existing Alloy systemd service was already shipping journal/syslog/auth logs to atlas Loki. The config was extended to add a second write target: the local Loki at `localhost:3100`. The `/var/log/claudebox/` directory is watched separately and its logs go only to the local endpoint — they don't flow to atlas.

## Stack Additions

```yaml
  loki:
    image: grafana/loki:3.4.2
    container_name: loki
    restart: unless-stopped
    ports:
      - "127.0.0.1:3100:3100"
    volumes:
      - /opt/appdata/grafana/loki-config/loki-config.yml:/etc/loki/local-config.yaml:ro
      - /opt/appdata/grafana/loki-data:/loki
    command: -config.file=/etc/loki/local-config.yaml
    networks:
      - claudebox-net

  grafana-image-renderer:
    image: grafana/grafana-image-renderer:latest
    container_name: grafana-image-renderer
    restart: unless-stopped
    environment:
      - ENABLE_METRICS=true
    networks:
      - claudebox-net
```

And two environment variables added to the Grafana service:

```yaml
    environment:
      - GF_RENDERING_SERVER_URL=http://grafana-image-renderer:8081/render
      - GF_RENDERING_CALLBACK_URL=http://grafana:3000/
```

## Loki Configuration

`/opt/appdata/grafana/loki-config/loki-config.yml`:

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2026-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 30d

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
```

The `delete_request_store: filesystem` entry under `compactor` is required for retention to actually work in Loki 3.4.x. Without it, `retention_enabled: true` and `retention_period` are accepted but silently ignored — log data accumulates indefinitely. This was a breaking change in 3.x that isn't prominently documented in the migration notes.

## Alloy Configuration

The Alloy config at `/etc/alloy/config.alloy` defines two write targets and routes log sources to them independently:

```alloy
// Atlas Loki (homelab infra logs)
loki.write "default" {
  endpoint {
    url = "http://192.168.x.x:3100/loki/api/v1/push"
  }
}

// Local Loki (claudebox self-healing agent logs)
loki.write "local" {
  endpoint {
    url = "http://localhost:3100/loki/api/v1/push"
  }
}

// Journal, syslog, auth.log → atlas
loki.source.journal "journal" {
  forward_to    = [loki.write.default.receiver]
  labels = { job = "journal", host = "claudebox" }
  // ...relabel rules
}

// /var/log/claudebox/*.log → local Loki only
local.file_match "claudebox_logs" {
  path_targets = [{
    __path__ = "/var/log/claudebox/*.log",
    job      = "self-healing",
    host     = "claudebox",
  }]
}

loki.source.file "claudebox_logs" {
  targets    = local.file_match.claudebox_logs.targets
  forward_to = [loki.write.local.receiver]
}
```

The routing split is intentional: infrastructure logs go to atlas for long-term retention and homelab-wide correlation; agent self-healing logs stay local for low-latency queries from local Grafana dashboards.

Alloy runs as a systemd service (`alloy.service`), not a Docker container or PM2 job. Changes to `/etc/alloy/config.alloy` take effect after `systemctl reload alloy` (or `restart` if adding new components).

## Loki Datasource in Grafana

Add a Loki datasource in Grafana pointing to `http://loki:3100` (container name resolves on `claudebox-net`). No authentication — the local instance has `auth_enabled: false`.

To query self-healing system logs:

```logql
{job="self-healing"}
```

Filter by a specific agent or component by adding a `filename` label (Alloy sets this automatically from the log file path):

```logql
{job="self-healing", filename="/var/log/claudebox/memory-pipeline.log"}
```

## Prerequisites

- The base Grafana stack from [grafana-claudebox](grafana-claudebox.md) already running
- Alloy installed and running as a systemd service (available from Grafana's APT repository)
- `/var/log/claudebox/` created and writable by the processes that generate self-healing logs
- Atlas Loki already running at its network address (for the non-local Alloy route)

## Integration Points

**Self-healing agents:** Any PM2 job or script that logs structured output to `/var/log/claudebox/*.log` gets automatically picked up by Alloy and shipped to local Loki. No additional configuration needed per-agent — just write to that directory.

**Grafana dashboards:** Local Loki shows up as a datasource alongside InfluxDB. Log panels can be placed on the same dashboards as agent metrics, giving a unified view of "what ran, what it cost, and what it logged."

**Atlas Loki:** Infrastructure logs from claudebox (journal, syslog, auth) continue to flow to atlas unchanged. The dual-destination config adds a second route; it doesn't replace the existing one.

**grafana-image-renderer:** Automatically used by Grafana when rendering panel images for alert notifications or manual snapshot exports. No per-dashboard configuration needed.

## Gotchas and Lessons Learned

**`delete_request_store` is required for retention in 3.4.x.** Loki 3.x split the retention enforcement mechanism out of the general compactor config. If you set `retention_enabled: true` without `delete_request_store`, the compactor starts fine, logs retention config on startup, and then does nothing with it. Disk usage grows without bound. Add `delete_request_store: filesystem` to the `compactor` block and restart Loki.

**Alloy reloads are graceful; restarts aren't.** `systemctl reload alloy` applies config changes in-place without dropping log tails. A restart works but briefly interrupts collection. For config changes that don't add new components, prefer reload.

**The image renderer needs matching Grafana versions.** `grafana/grafana-image-renderer:latest` tracks the current Grafana release. If you pin Grafana at a specific version and let the renderer drift, you may hit API incompatibilities. Either pin both or use `latest` for both.

**`/var/log/claudebox/` permissions.** Log files in this directory need to be readable by the user Alloy runs as (typically `alloy`, UID varies by install). If Alloy isn't picking up a log file, check ownership before debugging the config.

**Local Loki doesn't need SWAG.** The local Loki instance is internal-only — it listens on `127.0.0.1:3100` and is only accessed by Alloy (writing) and Grafana (querying over the Docker network). There's no reason to expose it through a reverse proxy.

## Standalone Value

The Alloy dual-destination pattern is worth extracting even if you're not building the rest of this stack. If you already run a centralized Loki instance and want to add local log collection for a specific application without routing everything through the central instance, the two-target Alloy config is the clean way to do it.

Local Loki with a 30-day retention window is also a reasonable setup for any homelab host that generates logs you want to query in Grafana but don't need to ship off-box. Self-signed certs, no auth, filesystem storage — it's deliberately simple.

## Related Docs

- [grafana-claudebox](grafana-claudebox.md) — base Grafana + InfluxDB stack this build extends
- [ai-cost-tracking](ai-cost-tracking.md) — the agent metrics pipeline feeding InfluxDB
- [agent-orchestration](agent-orchestration.md) — self-healing agent system that generates logs in `/var/log/claudebox/`
