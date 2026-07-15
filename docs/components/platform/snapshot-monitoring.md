# snapshot-monitoring

Two Btrfs snapshot probes plus the shared retention policy and alert library that back
them. Replaces the old `snapshot-space-probe.sh`, which read `df` on `/.snapshots/` —
meaningless on a single-device Btrfs layout, since `/`, `/opt`, `/home`, and
`/.snapshots` are all subvolumes of the same device and `df` reports whole-filesystem
usage, not snapshot-exclusive space.

- **Scripts:** `~/scripts/snapshot-capacity-probe.sh`, `~/scripts/snapshot-bloat-probe.sh`, `~/scripts/snapshot-retention.sh`
- **Shared config:** `~/scripts/snapshot-policy.conf`, `~/scripts/lib/alert-emit.sh`
- **Interpreter:** `bash`
- **Schedule:** capacity probe every 15 min; retention nightly 03:30; bloat probe nightly 03:45 (after btrbk 03:00 and retention 03:30, so it reflects post-prune state)
- **No listening port** — all run as PM2 cron batch jobs

## How It Works

### Capacity probe (the real safety net)

1. Runs `sudo btrfs filesystem usage -b /`, parses `Free (estimated)`, `Device unallocated`, and device size
2. Computes `pct_free`
3. Writes `btrfs_capacity` (fields: `free_bytes`, `unallocated_bytes`, `pct_free`) to InfluxDB
4. Alerts via `emit_alert` (see below): warning below 20% free, critical below 10% free

### Bloat probe (informational trend + drift detection)

1. Sources `snapshot-policy.conf` for the list of monitored locations
2. Enumerates snapshots via `sudo btrfs subvolume list -s /`
3. For each, runs `sudo btrfs filesystem du -s` and sums the **Exclusive** column into
   `total_exclusive_bytes` — "what deleting this snapshot alone would reclaim," not
   authoritative shared-space accounting (see Notes on why qgroups/squota aren't used)
4. Writes `btrfs_snapshot_bloat` (`total_exclusive_bytes`, `snapshot_count`,
   `oldest_manual_age_days`) and per-snapshot `btrfs_snapshot_excl` series to InfluxDB
5. Drift check: for each policy location with `drift_alert=yes`, warns if the oldest
   snapshot exceeds `max_age_days` plus a 1-day grace — this catches a dead retention
   cron rather than measuring absolute size (there is no absolute-GB threshold here,
   deliberately, to avoid recreating the old probe's arbitrary-threshold problem)

### Retention (pruning)

1. Sources the same `snapshot-policy.conf`
2. Prunes only locations tagged `managed_by=retention-cron` (currently: sysadmin
   `*-pre-*` snapshots under `/.snapshots/`) once they exceed that location's `max_age_days`
3. btrbk-managed locations are left alone — btrbk prunes those on its own schedule

### Shared alert emitter (`lib/alert-emit.sh`)

`emit_alert <key> <tier> <message>` — two-tier debounced alerting sourced by both probes:

- State: `/opt/appdata/snapshot-probe/<key>.state` → `<tier>:<epoch>`
- Sends on tier escalation (none→warning→critical), or after cooldown at the same tier
- Recovery: sends one "CLEARED" message when a condition drops back to `none`
- Routing: `warning` → `#sysadmin`; `critical` → `#alerts` + direct ntfy push
- A probe that can't reach InfluxDB or read btrfs also alerts critical
  (`key=probe-failure`) — a silent probe is a blind spot, which is what let the old
  design page uselessly while hiding real risk

## Configuration

**`snapshot-policy.conf`** — single source of truth for both the bloat probe and
retention pruning. One entry per location:
`glob|label|managed_by|max_age_days|drift_alert`.

| Location | Managed by | max_age_days | Drift alert |
|----------|-----------|---------------|--------------|
| pre-build (`/.snapshots/*-pre-*`) | retention-cron | 7 | yes |
| timeline (`@snapshots/btrbk/*`) | btrbk | 90 | yes |

Offsite (btrbk send/receive) is reserved as a future third row — not yet built.

| Setting | Value |
|---------|-------|
| Capacity warn / critical | pct_free < 20 / pct_free < 10 |
| Alert cooldowns | warning 24h, critical 6h |
| InfluxDB measurements | `btrfs_capacity`, `btrfs_snapshot_bloat`, `btrfs_snapshot_excl` |
| InfluxDB auth | `INFLUXDB_TOKEN` / `INFLUXDB_DATABASE` from `~/.secrets/forge.env` |
| Alert routing | warning → `#sysadmin`; critical → `#alerts` + ntfy |
| Sudoers (NOPASSWD, read-only) | `btrfs filesystem usage -b /`, `btrfs filesystem du -s /.snapshots/*`, `btrfs filesystem du -s /mnt/btrfs-root/@snapshots/btrbk/*` (plus pre-existing `subvolume list -s /` and `subvolume delete /.snapshots/*`) |

## Dependencies

- **InfluxDB** — time-series storage (Docker container, IP resolved dynamically via `docker inspect influxdb`)
- **Grafana** — dashboard/alert rule reading `btrfs_capacity` / `btrfs_snapshot_bloat`
- **btrbk** — creates the timeline snapshots this monitors
- **send-matrix.sh** — Matrix alerting, called by `lib/alert-emit.sh`
- **sudo** — required for all `btrfs` subcommands (narrowly scoped NOPASSWD entries)

## Operations

```bash
# Check status
pm2 show snapshot-capacity-probe
pm2 show snapshot-bloat-probe
pm2 show snapshot-retention

# Trigger manual run
pm2 restart snapshot-capacity-probe
bash -x ~/scripts/snapshot-bloat-probe.sh   # verbose, safe to run ad hoc

# Check current free space directly
sudo btrfs filesystem usage /

# Inspect alert debounce state
ls /opt/appdata/snapshot-probe/
cat /opt/appdata/snapshot-probe/capacity.state

# Retention log
tail -f ~/logs/snapshot-retention.log
```

## Notes

- **Why `btrfs filesystem du -s` and not qgroups:** qgroups slow down snapshot
  deletion — directly fights the nightly btrbk prune and the retention cron. `du -s`
  Exclusive has zero persistent overhead; it undercounts cross-snapshot-shared space,
  but that's acceptable for a trend/drift signal. squota (kernel 6.7+) is deferred
  until authoritative per-subvolume exclusive accounting is actually needed.
- **Sudoers path gotcha:** the NOPASSWD rules match literal absolute paths. Running
  from a relative cwd (e.g. `cd /.snapshots && btrfs ...`) does not match and falls
  through to a password prompt that fails non-interactively — always pass full paths.
- **Retention change:** pre-build snapshot retention was tightened from 14d to 7d in
  this redesign — pre-build snapshots' rollback value decays within hours of a clean
  build. The first run under the new policy pruned a one-time batch of snapshots aged
  7–14d.
- **Replaces `snapshot-space-probe.sh`:** the old probe read `df` on `/.snapshots/`
  and alerted on whole-device usage mislabeled as snapshot bloat (confirmed
  2026-07-14: deleting 42 stale snapshots moved the `df` figure by ~20 MB, versus its
  600 GiB alert threshold). The old `btrfs_snapshots used_bytes` InfluxDB series is no
  longer written; historical data is left in place.

## Related Docs

- [btrbk-daily.md](../foundation/btrbk-daily.md) — daily snapshot automation
- [btrfs-scrub-monthly.md](../foundation/btrfs-scrub-monthly.md) — monthly integrity scrub
- [disk-space-probe.md](disk-space-probe.md) — general disk usage monitoring
- [influxdb.md](../observability/influxdb.md) — InfluxDB service
