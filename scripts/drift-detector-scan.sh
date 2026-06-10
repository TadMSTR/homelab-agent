#!/bin/bash
set -euo pipefail

LOG="$HOME/logs/drift-detector-scan.log"
mkdir -p "$HOME/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Drift detector scan starting"

MEMORY_DIR="$HOME/.claude/memory/shared"
WINDOW_MINUTES=15

# Find build close-out memory notes written in the last WINDOW_MINUTES
RECENT=$(find "$MEMORY_DIR" \( -name "*close-out*" -o -name "*build*" \) -print0 2>/dev/null \
    | xargs -0 grep -l "tags:.*\[build" 2>/dev/null \
    | while read -r f; do
        [[ $(( $(date +%s) - $(stat -c %Y "$f") )) -lt $(( WINDOW_MINUTES * 60 )) ]] && echo "$f"
    done || true)

if [[ -z "$RECENT" ]]; then
    log "No recent build close-out notes — nothing to check"
    exit 0
fi

log "Recent build notes found: $(echo "$RECENT" | wc -l)"

# For each recent build note, extract the build name and check that declared
# outputs exist at the expected paths. Lightweight structural check only.

while IFS= read -r note; do
    build_name=$(grep -m1 "^build:" "$note" 2>/dev/null | awk '{print $2}' || echo "unknown")
    log "Checking drift for build: $build_name"

    # Check: audit report exists if build was not exempt
    audit_status=$(grep -m1 "^audit-status:" "$note" 2>/dev/null | awk '{print $2}' || echo "")
    if [[ "$audit_status" != "not-required" ]]; then
        report="$HOME/.claude/comms/artifacts/audit-reports/$build_name/handoff.md"
        [[ ! -f "$report" ]] && log "DRIFT: $build_name — audit report missing at $report"
    fi
done <<< "$RECENT"

log "Drift scan complete"
