#!/bin/bash
set -euo pipefail

LOCK=/tmp/memory-pipeline.lock
LOG="$HOME/.local/share/logs/memory-pipeline.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [memory-pipeline] $*" | tee -a "$LOG"; }

MATRIX="$HOME/scripts/send-matrix.sh"

mkdir -p "$(dirname "$LOG")"

# Prevent overlapping runs
exec 9>"$LOCK"
if ! flock -n 9; then
    log "ERROR: already running, exiting"
    exit 1
fi
trap 'rm -f "$LOCK"' EXIT

log "=== pipeline start ==="

run_step() {
    local name="$1"
    local script="$2"
    local step_timeout="${3:-0}"  # 0 = no timeout (backward compatible)
    log "--- $name: start ---"
    if [ "$step_timeout" -gt 0 ]; then
        if timeout "$step_timeout" bash "$script"; then
            log "--- $name: ok ---"
            return 0
        else
            local rc=$?
            if [ $rc -eq 124 ]; then
                log "--- $name: TIMED OUT after ${step_timeout}s ---"
                "$MATRIX" sysadmin "[memory-pipeline] $name TIMEOUT: exceeded ${step_timeout}s — killed. Check logs." || true
            else
                log "--- $name: FAILED (exit $rc) ---"
            fi
            return $rc
        fi
    else
        if bash "$script"; then
            log "--- $name: ok ---"
            return 0
        else
            local rc=$?
            log "--- $name: FAILED (exit $rc) ---"
            return $rc
        fi
    fi
}

# Step 1: memsearch-compact
# (memory-sync runs separately via memory-promote-daily at 11pm and memory-sync-weekly on Sundays)
export CALLED_FROM_PIPELINE=1
run_step "memsearch-compact" "/home/ted/.claude/scripts/memsearch-compact.sh" || {
    unset CALLED_FROM_PIPELINE
    log "memsearch-compact failed — skipping qmd-reindex"
    "$MATRIX" sysadmin \
        "memory-pipeline FAILED $(date '+%Y-%m-%d %H:%M') — memsearch-compact failed, check logs" || true
    exit 1
}
unset CALLED_FROM_PIPELINE

# Step 2: qmd-reindex (only reaches here if compact succeeded)
run_step "qmd-reindex" "/home/ted/scripts/qmd-refresh.sh" || {
    log "qmd-reindex failed"
    "$MATRIX" sysadmin \
        "memory-pipeline FAILED $(date '+%Y-%m-%d %H:%M') — qmd-reindex failed, check logs" || true
    exit 1
}

log "=== pipeline complete ==="
"$MATRIX" sysadmin \
    "memory-pipeline complete $(date '+%Y-%m-%d %H:%M') — memsearch-compact ✓ qmd-reindex ✓" || true
