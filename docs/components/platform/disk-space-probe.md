# disk-space-probe

Scheduled probe that writes disk usage and Btrfs block group fill percentages to
InfluxDB for Grafana dashboards. Alerts via Matrix when any monitored mount exceeds 85%.

- **Script:** `~/scripts/disk-space-probe.sh`
- **Interpreter:** `bash`
- **Schedule:** PM2 cron, every 15 minutes (`*/15 * * * *`)
- **Status:** stopped (replaced or superseded — check PM2)
- **No listening port** — runs as a batch job

## How It Works

1. Resolves InfluxDB container IP dynamically via `docker inspect`
2. Reads `df` usage for configured mounts (`/` as `root`, `/var/lib/docker` as `docker`)
3. Writes `disk_space` measurement to InfluxDB (line protocol, v3 API)
4. Reads Btrfs data block group fill via `btrfs filesystem usage /`
5. Writes `btrfs_data_pct` to InfluxDB
6. If any `df%` exceeds 85 — sends Matrix alert to `#agents`

## Configuration

| Setting | Value |
|---------|-------|
| Mounts monitored | `/` (root), `/var/lib/docker` (docker) |
| df threshold | 85% |
| InfluxDB measurement | `disk_space` |
| InfluxDB auth | `INFLUXDB_TOKEN` and `INFLUXDB_DATABASE` from `~/.secrets/forge.env` |
| Alert script | `~/scripts/send-matrix.sh` |
| Alert room | `#agents` |

## Dependencies

- **InfluxDB** — time-series storage (Docker container, port 8181 internal)
- **Grafana** — dashboards consuming the `disk_space` measurement
- **sudo** — required for `btrfs filesystem usage`
- **send-matrix.sh** — Matrix alerting

## Operations

```bash
# Check status
pm2 show disk-space-probe

# Trigger manual run
pm2 restart disk-space-probe

# Verify InfluxDB writes
# Check Grafana dashboard for disk_space series
```

## Related Docs

- [snapshot-monitoring.md](snapshot-monitoring.md) — snapshot capacity/bloat monitoring and retention
- [influxdb.md](../observability/influxdb.md) — InfluxDB service
