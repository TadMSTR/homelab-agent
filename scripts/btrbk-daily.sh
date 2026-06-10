#!/bin/bash
set -euo pipefail

LOG=/home/ted/logs/btrbk-daily.log
MATRIX_SCRIPT=/home/ted/scripts/send-matrix.sh

btrbk_run() {
  sudo btrbk run 2>&1 | tee -a "$LOG"
  return ${PIPESTATUS[0]}
}

echo "[$(date -Iseconds)] btrbk daily run starting" >> "$LOG"

if ! btrbk_run; then
  "$MATRIX_SCRIPT" "agents" "btrbk daily snapshot failed — check $LOG"
  exit 1
fi

echo "[$(date -Iseconds)] btrbk daily run complete" >> "$LOG"
