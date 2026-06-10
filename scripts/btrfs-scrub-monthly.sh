#!/bin/bash
set -euo pipefail

MATRIX_SCRIPT=/home/ted/scripts/send-matrix.sh
LOG=/home/ted/logs/btrfs-scrub.log
DEVICES=(/ /opt /home /var)

echo "[$(date -Iseconds)] Monthly Btrfs scrub starting" | tee -a "$LOG"

errors=0
for dev in "${DEVICES[@]}"; do
  echo "Scrubbing $dev..." | tee -a "$LOG"
  sudo btrfs scrub start -B "$dev" 2>&1 | tee -a "$LOG" || true
  status=$(sudo btrfs scrub status "$dev" 2>&1)
  echo "$status" >> "$LOG"
  # Match "Error summary:" but not "no errors found" — grep -q "error" false-positives on healthy output.
  # SECURITY[resolved]: Fixed false-positive alert. Audit: 2026-05-30/btrfs-snapshot-management-2026-05.
  if echo "$status" | grep -q "Error summary:" && ! echo "$status" | grep -q "no errors found"; then
    "$MATRIX_SCRIPT" "agents" "Btrfs scrub ERROR on $dev — check $LOG"
    errors=$((errors + 1))
  fi
done

if [[ $errors -eq 0 ]]; then
  echo "[$(date -Iseconds)] Scrub complete — no errors" | tee -a "$LOG"
else
  echo "[$(date -Iseconds)] Scrub complete — $errors device(s) with errors" | tee -a "$LOG"
fi
