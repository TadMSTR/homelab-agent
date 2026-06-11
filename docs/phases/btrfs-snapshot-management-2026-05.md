# Build: btrfs-snapshot-management-2026-05

**Date:** 2026-05-30
**Agent:** sysadmin

Installed btrbk for automated Btrfs timeline snapshots on forge, recovered 196GB of space by removing stale build-phase snapshots, and added monitoring (PM2 cron jobs + Grafana alert).

---

## What Was Built

### btrbk — automated timeline snapshots

btrbk installed and configured to snapshot three subvolumes daily. Config at `/etc/btrbk/btrbk.conf`:

```
snapshot_create        always
snapshot_preserve      7d 4w 3m
snapshot_preserve_min  2d
timestamp_format       long

volume /mnt/btrfs-root
    snapshot_dir  @snapshots/btrbk

    subvolume /mnt/btrfs-root/@rootfs
        snapshot_name  @rootfs

    subvolume /mnt/btrfs-root/@opt
        snapshot_name  @opt

    subvolume /mnt/btrfs-root/@home
        snapshot_name  @home
```

Retention: **7 daily / 4 weekly / 3 monthly**. Snapshots land at `/.snapshots/btrbk/`.

### /mnt/btrfs-root toplevel mount

Added to `/etc/fstab` so btrbk can reach subvolumes by path:

```
UUID=a5f8075f-...  /mnt/btrfs-root  btrfs  subvolid=5,compress=zstd,noatime,...  0  0
```

btrbk requires access to the Btrfs toplevel (subvolid=5) to create snapshots of named subvolumes.

### Space recovery

Deleted 30 stale build-phase snapshots (hand-created during prior platform build phases). Recovered **196 GB** — `/.snapshots/` reduced from 331 GB → 135 GB.

---

## PM2 Jobs

Three cron jobs added to PM2:

| PM2 ID | Name | Schedule | Script |
|--------|------|----------|--------|
| 34 | `btrbk-daily` | 03:00 daily | `~/scripts/btrbk-daily.sh` |
| 35 | `btrfs-scrub-monthly` | 1st of month, 02:00 | `~/scripts/btrfs-scrub-monthly.sh` |
| 36 | `snapshot-space-probe` | Every 15 min | `~/scripts/snapshot-space-probe.sh` |

**btrbk-daily** — runs `sudo btrbk run`, applies retention policy, sends Matrix alert to `agents` room on failure.

**btrfs-scrub-monthly** — runs `btrfs scrub` on the root filesystem. Sends a per-device Matrix alert to `agents` on completion with the scrub result.

**snapshot-space-probe** — measures `/.snapshots/` usage via `du -sb`, writes to InfluxDB (`btrfs_snapshots` measurement, `used_bytes` field, `host=forge` tag), and sends a Matrix alert to `agents` if usage exceeds 600 GB. Resolves the InfluxDB container IP dynamically via `docker inspect`.

---

## Monitoring

### InfluxDB measurement

```
btrfs_snapshots,host=forge used_bytes=<bytes> <unix_ts>
```

Written every 15 minutes by `snapshot-space-probe`. Queryable via Grafana datasource `InfluxDB` → `forge` database.

### Grafana alert

Alert rule created in Grafana:
- **Folder:** Forge
- **Rule group:** forge-infra
- **UID:** `afno7tfa450xsc`
- **Condition:** `used_bytes > 644245094400` (600 GiB)

---

## Security Audit

Two findings resolved, two accepted, one deferred:

| Finding | Status |
|---------|--------|
| `grep` false-positive in scan script | Fixed |
| logrotate missing for btrbk log | Fixed — added `/home/ted/logs/btrbk-daily.log` to logrotate |
| `NOPASSWD:ALL` in sudoers (pre-existing) | Accepted — pre-existing operator config |
| `snapshot-space-probe` writes to InfluxDB over HTTP (not HTTPS) | Accepted — internal Docker network; TLS would add complexity for no security gain |
| atlas `send_receive` | Deferred |

---

## Related Docs

- [influxdb.md](../components/observability/influxdb.md) — InfluxDB 3 Core write target
- [grafana.md](../components/grafana.md) — dashboard for snapshot usage
