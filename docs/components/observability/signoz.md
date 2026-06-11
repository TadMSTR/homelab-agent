# SigNoz

SigNoz is an open-source APM and observability platform built on OpenTelemetry. On forge it collects distributed traces, metrics, and logs from homelab-agent platform services via OTLP — including telemetry forwarded from claudebox's Alloy instance.

- **Version:** 0.118.0
- **URL:** `https://signoz.helmforge.me`
- **Compose:** `~/docker/signoz/docker-compose.yml`
- **Appdata:** `/opt/appdata/signoz/`
- **Network:** `signoz-internal` (isolated) + `forge-net` (signoz and signoz-otel-collector only)
- **SWAG proxy:** `signoz.helmforge.me` → `signoz:8080`

## Network Topology

![Analytics stack network topology](../../diagrams/analytics-stack-topology.drawio.svg)

*SigNoz stack (purple) and Langfuse stack (green) on forge, with claudebox Alloy forwarding telemetry over the LAN. Dashed lines indicate containers that are members of both their internal network and forge-net. Dashed container borders indicate one-shot services.*

## Stack

Six services: four long-running and two one-shot (init and migration). One-shot containers have `restart: on-failure` — they run once and exit 0 on success.

| Container | Image | Role |
|-----------|-------|------|
| `signoz` | `signoz/signoz:v0.118.0` | Web UI and API — port 8080 |
| `signoz-otel-collector` | `signoz/signoz-otel-collector:v0.144.2` | OTLP receiver — ports 4317 (gRPC) / 4318 (HTTP) |
| `signoz-clickhouse` | `clickhouse/clickhouse-server:25.5.6` | Primary datastore — traces, metrics, logs |
| `signoz-zookeeper` | `signoz/zookeeper:3.7.1` | ClickHouse cluster coordination |
| `signoz-init-clickhouse` | `clickhouse/clickhouse-server:25.5.6` | One-shot: stage `histogramQuantile` UDF binary |
| `signoz-migrator` | `signoz/signoz-otel-collector:v0.144.2` | One-shot: run schema migrations |

## Appdata Layout

```
/opt/appdata/signoz/
├── clickhouse/                          → /var/lib/clickhouse (signoz-clickhouse data)
├── clickhouse-user-scripts/             → /var/lib/clickhouse/user_scripts/ (histogramQuantile UDF)
├── zookeeper/                           → /bitnami/zookeeper
├── sqlite/                              → /var/lib/signoz/ (signoz.db — users, alerts)
├── cluster.xml                          → /etc/clickhouse-server/config.d/cluster.xml
├── config.xml                           → /etc/clickhouse-server/config.xml
├── users.xml                            → /etc/clickhouse-server/users.xml
├── custom-function.xml                  → /etc/clickhouse-server/custom-function.xml
├── otel-collector-config.yaml           → /etc/otel-collector-config.yaml
└── otel-collector-opamp-config.yaml     → /etc/manager-config.yaml
```

Config files were sourced from the SigNoz repo at tag `v0.118.0`. Do not regenerate from a newer tag without reviewing changes — schema changes in `config.xml` or `users.xml` can break ClickHouse on restart.

## Networking

Two Docker networks:

- **`signoz-internal`** — all six containers. Isolated from the rest of forge. Internal DNS resolves `signoz-clickhouse`, `signoz-zookeeper`, `signoz-otel-collector`, `signoz-migrator`.
- **`forge-net`** — `signoz` (web/API) and `signoz-otel-collector` only. SWAG proxies to `signoz:8080`; OTLP traffic from the LAN hits `signoz-otel-collector` on ports 4317/4318.

## OTLP Ports

```yaml
ports:
  - "4317:4317"   # OTLP gRPC — LAN-accessible
  - "4318:4318"   # OTLP HTTP
```

These are intentionally `0.0.0.0` (no localhost binding). claudebox uses Alloy to forward telemetry over the LAN (`<server-ip>:4317`). Any forge-net service or LAN host can send OTLP data directly.

## Config File Sources

Config files came from the SigNoz GitHub repo at the `v0.118.0` tag:

```
https://github.com/SigNoz/signoz/tree/v0.118.0/deploy/docker/
```

Files to grab: `clickhouse-setup/config.xml`, `clickhouse-setup/users.xml`, `clickhouse-setup/cluster.xml`, `clickhouse-setup/custom-function.xml`, `otel-collector-config.yaml`, `otel-collector-opamp-config.yaml`.

Place them in `/opt/appdata/signoz/` before first `docker compose up`.

## ZooKeeper Hostname Fix

**Critical gotcha:** `cluster.xml` as shipped in the SigNoz repo contains `zookeeper-1` as the ZooKeeper hostname:

```xml
<zookeeper>
    <node>
        <host>zookeeper-1</host>
        <port>2181</port>
    </node>
</zookeeper>
```

The compose file names the container `signoz-zookeeper`. If `cluster.xml` is used unmodified, ClickHouse fails to connect to ZooKeeper and all replica-table operations fail.

**Fix:** Edit `cluster.xml` before first deploy:
```xml
<host>signoz-zookeeper</host>
```

## histogramQuantile UDF (init container)

The `signoz-init-clickhouse` one-shot stages a `histogramQuantile` binary used by ClickHouse as a user-defined function for histogram percentile queries.

On initial deploy, it downloads the binary from GitHub releases and places it at `/var/lib/clickhouse/user_scripts/histogramQuantile`. For subsequent starts, it checks for the binary first and exits 0 immediately:

```bash
if [ -f /var/lib/clickhouse/user_scripts/histogramQuantile ]; then
  echo "histogramQuantile already present, skipping download"
  exit 0
fi
```

The binary was staged manually at initial deploy and verified. The download bypass guard was added as a security measure (M2 from 2026-04-15 audit) — SigNoz upstream does not publish checksums for this binary.

## Alloy Integration (claudebox → forge)

Alloy on claudebox is configured with an OTLP exporter targeting forge:

```alloy
otelcol.exporter.otlp "signoz" {
  client {
    endpoint = "<server-ip>:4317"
    tls { insecure = true }
  }
}
```

This requires Alloy to run with sufficient privileges to make outbound connections to forge's IP. On claudebox, Alloy's systemd unit runs as root. If you change the user, verify the outbound connection still works.

## Retention

Configured post-deploy via the SigNoz UI:

- **Settings → Retention Period** (metrics, traces, logs separately)
- Recommended starting points: traces 90 days, metrics 30 days, logs 14 days

Retention is stored in SigNoz's own ClickHouse tables and survives container restarts.

## Operator First-Login Steps

On a fresh deploy:
1. Navigate to `https://signoz.helmforge.me`
2. Complete the setup wizard — create admin account (no self-service registration after setup)
3. Verify: `curl -s https://signoz.helmforge.me/api/v1/version` → `{"setupCompleted":true}`
4. Configure retention: Settings → Retention Period
5. Note: SigNoz does not support Authentik or generic OIDC — only Google Workspace SSO is available for enterprise auth. Admin account is the primary auth mechanism on forge.

## Security

Post-deploy security state from audit 2026-04-15:

| Finding | Status |
|---------|--------|
| pprof endpoint reachable from forge-net (L2) | ✓ fixed — `localhost:1777` in `otel-collector-config.yaml` |
| Config files world-readable 664 (L3) | ✓ fixed — XML: `640`, YAML: `644` (ClickHouse runs as root; collector runs UID 10001 with no forge group mapping) |
| Retention not configured (L5) | ✓ fixed — configured via UI post-deploy |
| Volumes not backed up (L6) | ✓ fixed — covered by `/home/ted/scripts/docker-stack-backup.sh` (2 AM daily) |
| No Authelia/SSO layer on SWAG proxy (M1) | deferred — SigNoz only supports Google Workspace SSO; not compatible with Authentik. Native admin auth remains the gate. |
| signoz-init-clickhouse binary without checksum (M2) | ✓ fixed — binary pre-staged; existence guard added to init container |
| signoz-zookeeper runs as root | acknowledged — Bitnami image drops privileges internally; container on `signoz-internal` only, no external exposure |
| ClickHouse empty password in users.xml | acknowledged — SigNoz upstream default; service on `signoz-internal` only, no host port |

`.env` is `600 ted:ted`. OTLP ports 4317/4318 are intentionally LAN-accessible (pre-approved in build plan).

## Backup

Covered by `~/scripts/docker-stack-backup.sh` on forge. Stop → `sudo tar` → restart. Backup destination: `/mnt/atlas/forge/backups/docker-backups/`. Schedule: 2 AM daily.

Priority order if restoring selectively:
1. `sqlite/` — SigNoz users, alerts, dashboard config (small, critical)
2. `clickhouse/` — APM data (large; reconstructable from re-ingestion if needed)
3. `zookeeper/` — ClickHouse cluster state (regenerates on startup from ClickHouse metadata)
4. `clickhouse-user-scripts/` — histogramQuantile binary (re-downloadable)

## Related Docs

- [phase-analytics-stack.md](../../phases/phase-analytics-stack.md) — build narrative for this stack
- [langfuse.md](langfuse.md) — companion LLM observability stack
