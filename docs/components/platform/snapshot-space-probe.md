# snapshot-space-probe

Scheduled probe that writes Btrfs snapshot directory usage to InfluxDB and alerts via
Matrix when `/.snapshots/` exceeds 600 GB.

- **Script:** `~/scripts/snapshot-space-probe.sh`
- **Interpreter:** `bash`
- **Schedule:** PM2 cron, every 15 minutes (`*/15 * * * *`)
- **No listening port** — runs as a batch job

## How It Works

1. Resolves InfluxDB container IP dynamically via `docker inspect`
2. Reads `/.snapshots/` usage in bytes via `df -B1`
3. Writes `btrfs_snapshots` measurement (field: `used_bytes`) to InfluxDB via line protocol
4. If usage exceeds 600 GiB (644245094400 bytes) — sends Matrix alert to `#agents`
5. On InfluxDB write failure — sends error alert to `#agents`

## Configuration

| Setting | Value |
|---------|-------|
| Snapshot dir | `/.snapshots/` |
| Threshold | 600 GiB |
| InfluxDB measurement | `btrfs_snapshots` |
| InfluxDB auth | `INFLUXDB_TOKEN` and `INFLUXDB_DATABASE` from `~/.secrets/forge.env` |
| Alert script | `~/scripts/send-matrix.sh` |
| Alert room | `#agents` |

Grafana alert rule also configured (Forge folder, rule group `forge-infra`) to fire at
the same 600 GB threshold.

## Dependencies

- **InfluxDB** — time-series storage (Docker container, port 8181 internal)
- **Grafana** — dashboards and alert rules consuming `btrfs_snapshots` measurement
- **btrbk** — creates the snapshots being monitored
- **send-matrix.sh** — Matrix alerting

## Operations

```bash
# Check status
pm2 show snapshot-space-probe

# Trigger manual run
pm2 restart snapshot-space-probe

# Check current snapshot usage
df -h /.snapshots/

# View Grafana alert
# grafana.helmforge.me → Alerting → forge-infra rule group
```

## Related Docs

- [btrbk-daily.md](../foundation/btrbk-daily.md) — daily snapshot automation
- [btrfs-scrub-monthly.md](../foundation/btrfs-scrub-monthly.md) — monthly integrity scrub
- [disk-space-probe.md](disk-space-probe.md) — general disk usage monitoring
- [influxdb.md](../observability/influxdb.md) — InfluxDB service
