#!/usr/bin/env bash
# memsearch index daemon — fast tier (working + session memory)
# Polls every 60s. These dirs change constantly during active sessions.

set -euo pipefail

MEMSEARCH=/opt/venvs/memsearch/bin/memsearch
MEMORY_DIR=/home/ted/.claude/memory
SESSION_BASE=/home/ted/.claude/projects
INTERVAL=60

LOG_DIR="$HOME/logs/memsearch"
LOG_RETAIN_DAYS=30
mkdir -p "$LOG_DIR"
find "$LOG_DIR" -maxdepth 1 -name "watch-fast-*.log" -mtime +"$LOG_RETAIN_DAYS" -delete 2>/dev/null || true
chmod 750 "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/watch-fast-${TIMESTAMP}.log"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }

log "Starting memsearch fast-tier index daemon (interval: ${INTERVAL}s)"

index_fast() {
    log "Indexing $MEMORY_DIR..."
    if "$MEMSEARCH" index "$MEMORY_DIR" >>"$LOG_FILE" 2>&1; then
        log "Index complete: $MEMORY_DIR"
    else
        log "Index failed (exit $?): $MEMORY_DIR"
    fi

    # SECURITY[accepted]: glob follows symlinks. Exploitation requires write access to
    # $SESSION_BASE (/home/ted/.claude/projects/), a fully ted-controlled path.
    # Accepted risk. Audit: 2026-05-28/memsearch-forge-infra-2026-05.
    for session_dir in "$SESSION_BASE"/*/.memsearch/memory/; do
        [ -d "$session_dir" ] || continue
        log "Indexing $session_dir..."
        if "$MEMSEARCH" index "$session_dir" >>"$LOG_FILE" 2>&1; then
            log "Index complete: $session_dir"
        else
            log "Index failed (exit $?): $session_dir"
        fi
    done
}

log "Initial index run..."
index_fast
log "Initial index done."

while true; do
    sleep "$INTERVAL"
    index_fast
done
