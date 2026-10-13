# Grafana Alloy

Grafana Alloy is the log collector for forge, replacing EOL Promtail. It discovers running
Docker containers, tails their logs plus two sets of agent log files on the host, and ships
everything to Loki under tenant `forge`. On forge, Alloy collects logs only. System metrics
come from Telegraf.

A second Alloy container, [`alloy-relay`](alloy-relay.md), runs in the same compose project.
It doesn't collect anything on forge. It's the ingest relay for logs pushed from a remote
fleet host. This doc covers the collector (`alloy`) and Loki's tenant model.

- **Image:** `grafana/alloy:v1.20.1` (tag plus `@sha256` digest pinned in compose)
- **Compose:** `~/docker/observability/docker-compose.yml` (project `observability`)
- **Config:** `/opt/appdata/observability/alloy/config.alloy` (mounted `:ro`)
- **Storage:** `/opt/appdata/observability/alloy/data` → `/var/lib/alloy/data`
- **Network:** `forge-monitoring`

## Pipelines

| Source | Input | Labels added | Path to Loki |
|--------|-------|--------------|--------------|
| `loki.source.docker "containers"` | Every running container via `docker.sock` | `job="docker"`, `container`, `stack`, `compose_service` | `loki.process "docker_redact"` → `loki.write "loki"` |
| `loki.source.file "scoped_mcp"` | scoped-mcp per-session audit/ops JSONL (`/var/agent-logs/*/{audit,ops}/*.jsonl`) | `job="scoped-mcp"`, `stream`, `agent` | `loki.relabel` → `loki.write "loki"` |
| `loki.source.file "githost_mcp"` | githost-mcp per-agent logs (`/var/githost-logs/githost-mcp-*.log`) | `job="githost-mcp"`, `agent` | `loki.relabel` → `loki.write "loki"` |

The two file sources read host directories bind-mounted read-only into the container.

### Docker labels

`discovery.relabel` maps three container-identity meta-labels onto log entries:

- `container` — container name, leading `/` stripped
- `stack` — compose project, which matches the stack directory under `~/docker/`
- `compose_service` — compose service name (differs from `container` where `container_name` is overridden)

Only identity labels are used. `discovery.docker` emits one target per container per
network/port, and `loki.source.docker` keeps only the first target per container ID. A label
taken from `__meta_docker_network_*` or `__meta_docker_port_*` would therefore depend on
Docker API ordering.

### Redaction

`loki.process "docker_redact"` runs a `stage.replace` over every Docker line that rewrites
`renderKey=<value>` to `renderKey=<redacted>`. The Grafana image renderer logs each `/render`
URI at INFO, and the render key is a short-lived Editor-role credential. Only the capture
group is replaced, so the rest of the request line (status, duration) survives.

### Write

```alloy
loki.write "loki" {
  endpoint {
    url       = "http://loki:3100/loki/api/v1/push"
    tenant_id = "forge"
  }
}
```

`tenant_id` sets the `X-Scope-OrgID` header on every push. Loki requires it (see
[Loki tenancy](#loki-tenancy) below).

## Loki Tenancy

Loki runs multi-tenant (`auth_enabled: true`). Every request needs an `X-Scope-OrgID`
header, and a request without one gets `401 no org id`. `/ready` and `/metrics` still
answer without the header.

| Tenant | Written by | Read by |
|--------|-----------|---------|
| `forge` | forge's Alloy (`tenant_id = "forge"`) | Grafana `Loki` datasource and loki-mcp's default, both as `forge\|fake` |
| `argus` | `alloy-relay` only, forced per entry | Grafana `Loki (argus)` datasource, loki-mcp with `tenant="argus"` |
| `fake` | Nothing. Holds data written before multi-tenancy was turned on | The `forge\|fake` read bridge, until the data ages out of retention |

There is one tenant per host. The tenant is the boundary, so a query against `forge` can't
return a remote host's lines however those lines are labelled.

**The header routes requests. It doesn't authenticate them.** Anything that can reach Loki
can pick any tenant. What keeps a remote host out of `forge` is the network layout: Loki's
only pusher on the ingest network is `alloy-relay`, the reverse proxy clears any incoming
`X-Scope-OrgID`, and the relay overwrites the tenant on every entry anyway. See
[alloy-relay.md](alloy-relay.md).

### Configuration

Two files in `~/docker/observability/loki-config/`, both mounted read-only:

- **`local-config.yaml`** — main config.
  - `auth_enabled: true` turns tenancy on.
  - `querier.multi_tenant_queries_enabled: true` lets query endpoints accept `a|b`. The
    `forge|fake` bridge needs it, and so does the remote host datasource's two-tenant header
    (below). Tail and push still refuse more than one tenant.
  - `runtime_config.file: /etc/loki/runtime-overrides.yaml` loads the per-tenant limits.
  - `limits_config` is the default for tenants with no override (`forge`, `fake`): 30-day
    retention, 90 days for `job="scoped-mcp"` and `job="githost-mcp"`, 16/32 MB ingest
    rate/burst, 15000 streams.
- **`runtime-overrides.yaml`** — per-tenant overrides, re-read every 10 seconds with no
  restart. The file must be mode `644`. Loki runs as uid 10001 and crash-loops on a `600` file.

```yaml
overrides:
  argus:
    retention_period: 720h               # 30d
    retention_stream:
      - selector: '{job="journal"}'
        priority: 1
        period: 2160h                    # 90d
    ingestion_rate_mb: 4
    ingestion_burst_size_mb: 8
    max_global_streams_per_user: 2000
    allow_structured_metadata: false
```

A per-tenant `retention_stream` **replaces** the global list for that tenant. It doesn't add
to it. Its selectors don't need a `host=` matcher, because the tenant already scopes them.

`allow_structured_metadata: false` makes Loki refuse any remote host entry that carries
structured metadata. The entry gets an HTTP 400 and is counted as
`loki_discarded_samples_total{reason="disallowed_structured_metadata"}`, and the rest of the
batch still lands. This is the real control against a pushed structured-metadata key
posing as a label or as the tenant. The relay's drop list is defence in depth.

### Readers

- **Grafana:** `Loki` reads `forge|fake`. `Loki (argus)` reads `argus|argus-none`, where
  `argus-none` is a tenant nothing writes to. With two tenants in the header, Loki stamps its
  own `__tenant_id__` on every result and renames a pushed one. The cost is that a
  multi-tenant query can't live-tail.
- **loki-mcp:** v0.2.0+ reads `forge|fake` by default. Every tool takes an optional per-call
  `tenant` argument, limited to the values allowlisted in `LOKI_TENANTS`.

### Rollback

Set `auth_enabled: false` and restart Loki. Reads and writes go back to the single implicit
tenant `fake`. Nothing written while tenancy was on is lost.

## Critical: HTTP Listen Address

Alloy's default HTTP listener binds to `127.0.0.1:12345`. Inside Docker, this means
Prometheus cannot scrape Alloy's `/metrics` endpoint — `127.0.0.1` resolves to the
container's loopback, not the host. The compose command overrides this:

```yaml
command:
  - run
  - /etc/alloy/config.alloy
  - --server.http.listen-addr=0.0.0.0:12345
  - --storage.path=/var/lib/alloy/data
```

Without the listen-address flag, Alloy's own metrics are invisible to Prometheus.

## Persistent Storage

`--storage.path` is set explicitly and bind-mounted to the host. Alloy's default
(`data-alloy/`) is relative to the working directory (`/`), which puts it in the
container's writable layer. That directory holds `loki.source.docker`'s positions file
(read offsets) and `loki.write`'s WAL.

Without the bind mount, any `compose down`/`up -d` (a nightly backup job, for example)
throws both away. Alloy then re-tails every container from the start of its log, and Loki
rejects the replay as `greater_than_max_sample_age`, `too_far_behind` or `rate_limited`.

## Docker Group Access

Like Telegraf, Alloy reads `/var/run/docker.sock` for container discovery and logs. It runs
as root (the image default) with `no-new-privileges`. Root is needed for the socket and for
reading the bind-mounted host log directories. The Docker group GID on forge is `989`, and it
must be given as a number:

```yaml
group_add:
  - "989"    # docker group — must be numeric
```

## Operations

```bash
# Restart the collector
cd ~/docker/observability && docker compose restart alloy

# Logs
docker logs --tail 100 alloy

# Query Loki directly — the tenant header is mandatory
curl -s -H 'X-Scope-OrgID: forge' \
  'http://127.0.0.1:3100/loki/api/v1/labels' | jq

# Per-tenant discards (rate limits, disallowed structured metadata)
curl -s http://127.0.0.1:3100/metrics | grep loki_discarded_samples_total
```

## Related Docs

- [alloy-relay.md](alloy-relay.md) — ingest relay for remote host log pushes
- [loki-mcp.md](loki-mcp.md) — read-only LogQL MCP server
- [prometheus.md](prometheus.md) — scrapes `alloy:12345`
- [signoz.md](signoz.md) — claudebox Alloy (different config: OTLP exporter to forge)
