#!/bin/bash
set -euo pipefail
# Writes snapshot dir usage to InfluxDB for Grafana dashboards.
# Also sends a Matrix alert if /.snapshots/ exceeds 600GB.
# InfluxDB runs in Docker; resolves IP dynamically.
source <(grep -E "^INFLUXDB_(TOKEN|DATABASE)" ~/.secrets/forge.env)
MATRIX_SCRIPT=/home/ted/scripts/send-matrix.sh
THRESHOLD_BYTES=644245094400  # 600 GiB

INFLUXDB_IP=$(docker inspect influxdb --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
if [[ -z "$INFLUXDB_IP" ]]; then
  "$MATRIX_SCRIPT" "agents" "snapshot-space-probe: could not resolve influxdb container IP — probe failed"
  exit 1
fi

usage_bytes=$(df -B1 --output=used /.snapshots/ 2>/dev/null | tail -1 | tr -d ' ')
usage_gb=$(( usage_bytes / 1073741824 ))

if ! curl -sf -X POST "http://${INFLUXDB_IP}:8181/api/v3/write_lp?db=${INFLUXDB_DATABASE}&precision=second" \
  -H "Authorization: Bearer ${INFLUXDB_TOKEN}" \
  -H "Content-Type: text/plain" \
  --data-raw "btrfs_snapshots,host=forge used_bytes=${usage_bytes} $(date +%s)"; then
  "$MATRIX_SCRIPT" "agents" "snapshot-space-probe: InfluxDB write failed — check probe script and influxdb container"
  exit 1
fi

if (( usage_bytes > THRESHOLD_BYTES )); then
  "$MATRIX_SCRIPT" "agents" "/.snapshots/ exceeds 600GB on forge (${usage_gb}GB) — run btrbk cleanup or delete stale snapshots"
fi
