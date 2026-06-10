#!/bin/bash
set -euo pipefail
# Writes disk and btrfs block group usage to InfluxDB for Grafana dashboards.
# Sends a Matrix alert if df% > 85. btrfs block group fill is written to InfluxDB only (no alert).
# InfluxDB runs in Docker; resolves IP dynamically.
source <(grep -E "^INFLUXDB_(TOKEN|DATABASE)" ~/.secrets/forge.env)
MATRIX_SCRIPT=/home/ted/scripts/send-matrix.sh
DF_THRESHOLD=85
TIMESTAMP=$(date +%s)

INFLUXDB_IP=$(docker inspect influxdb --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
if [[ -z "$INFLUXDB_IP" ]]; then
  "$MATRIX_SCRIPT" "agents" "disk-space-probe: could not resolve influxdb container IP — probe failed"
  exit 1
fi

influx_write() {
  local payload="$1"
  if ! curl -sf -X POST "http://${INFLUXDB_IP}:8181/api/v3/write_lp?db=${INFLUXDB_DATABASE}&precision=second" \
    -H "Authorization: Bearer ${INFLUXDB_TOKEN}" \
    -H "Content-Type: text/plain" \
    --data-raw "$payload"; then
    "$MATRIX_SCRIPT" "agents" "disk-space-probe: InfluxDB write failed — check probe script and influxdb container"
    exit 1
  fi
}

alert_sent=0

# --- df% checks ---
declare -A MOUNTS=(
  [root]="/"
  [docker]="/var/lib/docker"
)

for label in "${!MOUNTS[@]}"; do
  mount="${MOUNTS[$label]}"
  df_pct=$(df --output=pcent "$mount" 2>/dev/null | tail -1 | tr -d ' %')
  influx_write "disk_space,host=forge,mount=${label} df_pct=${df_pct} ${TIMESTAMP}"
  if (( df_pct > DF_THRESHOLD )); then
    "$MATRIX_SCRIPT" "agents" "disk-space-probe: ${mount} is ${df_pct}% full on forge — investigate or expand"
    alert_sent=1
  fi
done

# --- btrfs data block group fill% ---
btrfs_data_pct=$(sudo btrfs filesystem usage / 2>/dev/null \
  | grep "^Data," \
  | grep -oP '\d+\.\d+(?=%)' \
  | tail -1)

if [[ -n "$btrfs_data_pct" ]]; then
  influx_write "disk_space,host=forge,mount=btrfs_data btrfs_data_pct=${btrfs_data_pct} ${TIMESTAMP}"
fi
