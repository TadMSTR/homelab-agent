# Grafana Dashboards

Grafana dashboards deployed on forge for monitoring agent infrastructure and supporting
services. All dashboards are accessible at `https://grafana.<domain>` (Authentik OIDC auth)
and live in the **Forge** folder.

Every dashboard, datasource, contact point, notification policy and alert rule is
**file-provisioned** (Grafana as code). Nothing exists only in Grafana's database, so a DB
rebuild loses no configuration.

## Provisioning Layout

Grafana mounts the provisioning tree read-only:

```yaml
volumes:
  - /opt/appdata/observability/grafana:/var/lib/grafana
  - /opt/appdata/observability/grafana/provisioning:/etc/grafana/provisioning:ro
```

```
/opt/appdata/observability/grafana/provisioning/
├── alerting/
│   ├── contact-points.yaml         # doorman-matrix, ntfy-direct
│   ├── notification-policies.yaml  # default → doorman-matrix; route=selfmon → ntfy-direct
│   └── rules-forge.yaml            # rule groups forge-selfmon, forge-host, argus-host
├── dashboards/
│   ├── dashboards.yml              # file provider "forge" → folder Forge
│   └── forge/                      # one JSON file per dashboard (17)
├── datasources/
│   └── datasources.yml             # 12 datasources, every one with a pinned uid
└── plugins/
    └── README.md                   # placeholder only (see below)
```

The provisioning files are kept in a private config repo and deployed to the appdata path;
that repo, not the Grafana UI, is the source of truth.

**Consequences of file provisioning:**

- Provisioned dashboards are **read-only in the Grafana UI**. Save-as-copy works for
  experiments, but changes only persist when made in the JSON files.
- grafana-mcp's dashboard-write tools fail on every dashboard by design (see
  [grafana-mcp.md](grafana-mcp.md)).
- Every datasource carries an explicit `uid:`. Panels and alert rules refer to datasources
  by uid, so new dashboards and rules must use the pinned uids from `datasources.yml`.
- `plugins/` holds only a README. Grafana logs an error at every start if the directory is
  missing, but it reads only `*.yaml`/`*.yml` there, so the README is never loaded. Plugins
  themselves are installed via `GF_PLUGINS_PREINSTALL`.

## Provisioned Dashboards

| Title | File | uid | Main datasource(s) |
|-------|------|-----|--------------------|
| Agent Activity & Log Volume | `agent-activity.json` | `fd7f4302-…` | Loki |
| Alloy Pipeline Health | `alloy-pipeline-health.json` | `1d8568e4-…` | Prometheus |
| argus — Node Exporter Full | `argus-node.json` | `argus-node` | Prometheus, Loki |
| Disk Space | `disk-space.json` | `forge-disk-space` | InfluxDB |
| Docker Container Logs | `docker-container-logs.json` | `203a2493-…` | Loki |
| GPU & Ollama Queue | `gpu-ollama.json` | `gpu-ollama-forge` | Prometheus |
| Grafana Self-Health | `grafana-self-health.json` | `995b5baa-…` | Prometheus |
| Host Overview | `host-overview.json` | `forge-host-overview` | InfluxDB |
| Host System Metrics | `host-system-metrics.json` | `e609619b-…` | InfluxDB |
| Log Pipeline | `log-pipeline.json` | `forge-log-pipeline` | Loki, Prometheus |
| Notification Egress | `notification-egress.json` | `forge-notification-egress` | Prometheus |
| Redis/Dragonfly/Valkey Fleet | `redis-fleet.json` | `redis-fleet` | Redis datasources |
| scoped-mcp Tool Usage | `scoped-mcp-tool-usage.json` | `scoped-mcp-tool-usage` | Loki |
| SearXNG-MCP Operations | `searxng-mcp-ops.json` | `searxng-mcp-ops` | ClickHouse, Loki, Redis |
| Technitium DNS (argus) | `technitium-argus.json` | `forge-technitium-argus` | Prometheus |
| Vikunja | `vikunja.json` | `jpQqhQEmk` | Prometheus |
| webhook-doorman | `webhook-doorman.json` | `forge-webhook-doorman` | Prometheus |

Dashboards that were originally built in the UI were exported with their uids unchanged,
so existing links and bookmarks still resolve. Host System Metrics overlaps Host Overview;
both are kept for now.

The two dashboards below are described in more detail.

### SearXNG-MCP Operations

Operational dashboard for the searxng-mcp server, covering search and fetch performance,
cache behavior, and error tracking.

**Datasources:**

| Source | Type | What it provides |
|--------|------|------------------|
| SigNoz ClickHouse | Traces/metrics | Search/fetch latency, tool call counts, error rates |
| scoped-mcp traces | Distributed traces | End-to-end request flow through the MCP proxy layer |
| Loki | Logs | Error log panels (filtered to searxng-mcp) |
| Dragonfly (searxng-dragonfly) | Redis metrics | Cache hit/miss ratio, key count, memory usage |

The SigNoz ClickHouse datasource reaches ClickHouse through a small HTTP-only proxy
container (`signoz-clickhouse-proxy`, port 8123) as a dedicated read-only ClickHouse user,
rather than attaching ClickHouse itself to the `grafana-datasources` network.

**Key panels:**
- Search request volume and latency (p50/p95/p99)
- Fetch tier cascade breakdown (Kiwix / Hister / direct / Wayback)
- Cache hit rate over time
- Error log stream (Loki)

### Redis/Dragonfly/Valkey Fleet

Health monitoring dashboard for all 7 Redis-compatible instances running on forge.

**Datasources:**

| Source | Type | What it provides |
|--------|------|------------------|
| Grafana Redis datasource | Direct connection | Per-instance metrics via `grafana-datasources` network |

**Monitored instances:**

| Instance | Stack | Purpose |
|----------|-------|---------|
| `searxng-dragonfly` | searxng | searxng-mcp cache + SearXNG result cache |
| `agent-dragonfly` | agent-platform | Agent session state, HITL gate |
| `langfuse-dragonfly` | langfuse | Langfuse application cache |
| `firecrawl-redis` | firecrawl | Firecrawl job queue |
| `oqp-valkey` | agent-platform | Ollama queue proxy embedding cache |
| `patchmon-valkey` | patchmon | PatchMon cache |
| `plane-valkey` | plane | Plane project management cache |

**Key panels:**
- Connected clients per instance
- Memory usage and fragmentation ratio
- Commands processed per second
- Key count and eviction rate
- Instance availability (up/down)

## Alerting

Alert rules live in `alerting/rules-forge.yaml`, in three groups: `forge-selfmon`
(observability pipeline self-monitoring), `forge-host` (host and container health) and
`argus-host` (the second fleet host). Routing is in `notification-policies.yaml`:

| Match | Contact point | Path |
|-------|---------------|------|
| default | `doorman-matrix` | webhook → Matrix |
| `route = selfmon` | `ntfy-direct` | webhook → ntfy, bypassing the stack being monitored |

Both contact points are webhooks. Their secrets (the webhook bearer token and the ntfy
URL) are interpolated from environment variables, never written into the YAML.

## Infrastructure

- **Grafana container:** `grafana` in the observability stack, `127.0.0.1:3003` → 3000
- **Network:** `grafana-datasources` bridge connects Grafana to all Redis instances and the
  ClickHouse proxy
- **Dashboard provisioning:** file-provisioned from
  `/opt/appdata/observability/grafana/provisioning/` (mounted `:ro`); see above
- **Auth:** All Redis instances use `requirepass` (or `DFLY_requirepass` for Dragonfly)

## Operations

```bash
# Check Grafana health
curl -s http://127.0.0.1:3003/api/health | jq .

# List dashboards via API
curl -s -H "Authorization: Bearer $GRAFANA_API_KEY" \
  http://127.0.0.1:3003/api/search?type=dash-db | jq '.[].title'

# View dashboard in browser
# https://grafana.<domain>
```

### Changing provisioned config

1. Edit the file in the config repo and deploy it to the provisioning path.
2. Reload without a restart, using **admin** basic auth (the grafana-mcp service account
   lacks `provisioning:reload`). Read the admin password inside a script; never print it.

   ```
   POST /api/admin/provisioning/dashboards/reload
   POST /api/admin/provisioning/datasources/reload
   POST /api/admin/provisioning/alerting/reload
   ```

   `docker restart grafana` is the fallback. A restart is not a recreate, so the
   container's environment does not change.

### Operating note: new `$VARS` in provisioning files

Provisioning files interpolate environment variables (datasource passwords, webhook
tokens, the ntfy URL). Grafana receives **only** the variables listed explicitly in its
compose `environment:` block, each passed from the stack `.env`; no shared secrets file
reaches the container.

**A new `$VAR` referenced in a provisioning file needs a matching `environment:` line in
compose. Without one it interpolates to an empty string with no error**, so a datasource
silently fails auth or a contact point posts to an empty URL. Adding the line means
**recreating** the container (`docker compose up -d grafana`); a reload or restart does not
pick up new environment variables.

## Dependencies

- SigNoz ClickHouse (traces/metrics backend), via `signoz-clickhouse-proxy`
- Loki (log aggregation)
- InfluxDB and Prometheus (host and service metrics)
- All 7 Redis-compatible instances (via `grafana-datasources` network)
- `grafana-datasources` Docker network must include both Grafana and target containers
