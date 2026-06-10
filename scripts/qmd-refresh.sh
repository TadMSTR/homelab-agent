#!/usr/bin/env bash
# qmd-refresh — re-index QMD collections and update embeddings.
# Run periodically (hourly via PM2 cron) to keep agent-memory and other
# collections fresh as memory files are written.

set -euo pipefail

LOG_DIR="$HOME/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/qmd-refresh.log"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

log "qmd update..."
qmd update --pull >>"$LOG_FILE" 2>&1

log "qmd embed..."
qmd embed >>"$LOG_FILE" 2>&1

log "Done."
