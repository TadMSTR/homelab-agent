#!/bin/bash
set -euo pipefail

LOG="$HOME/logs/build-unblock-scan.log"
PLANS_DIR="$HOME/.claude/comms/artifacts/build-plans"

mkdir -p "$HOME/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

matrix_notify() {
    # Uses send-matrix.sh (Matrix client API + bearer token) rather than matrix-mcp
    # directly — matrix-mcp's streamable-http transport requires a session handshake
    # that a one-shot curl can't satisfy.
    local msg="$1"
    "$HOME/scripts/send-matrix.sh" agents "$msg" >> "$LOG" 2>&1 || true
}

log "Build unblock scan starting"

INDEX="$PLANS_DIR/index.md"
[[ ! -f "$INDEX" ]] && log "No index.md found — nothing to scan" && exit 0

NEWLY_UNBLOCKED=()

declare -A COMPLETED_PLANS
declare -A PLAN_DEPS
declare -A PLAN_STATUS
current_plan=""

while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+(.+) ]]; then
        current_plan="${BASH_REMATCH[1]}"
    elif [[ -n "$current_plan" && "$line" =~ status:[[:space:]]*complete ]]; then
        COMPLETED_PLANS["$current_plan"]=1
        PLAN_STATUS["$current_plan"]="complete"
    elif [[ -n "$current_plan" && "$line" =~ depends-on:[[:space:]]*(.+) ]]; then
        PLAN_DEPS["$current_plan"]="${BASH_REMATCH[1]// /}"
    fi
done < "$INDEX"

for plan in "${!PLAN_DEPS[@]}"; do
    dep="${PLAN_DEPS[$plan]}"
    [[ "${PLAN_STATUS[$plan]:-}" == "complete" ]] && continue
    for completed in "${!COMPLETED_PLANS[@]}"; do
        if [[ "$completed" == "$dep" ]]; then
            NEWLY_UNBLOCKED+=("$plan")
            break
        fi
    done
done

if [[ ${#NEWLY_UNBLOCKED[@]} -gt 0 ]]; then
    NAMES=$(printf '%s, ' "${NEWLY_UNBLOCKED[@]}")
    log "Newly unblocked: ${NAMES%, }"
    matrix_notify "**[UNBLOCKED]** Build plans ready: ${NAMES%, }. Check ~/.claude/comms/artifacts/build-plans/index.md"
else
    log "No newly unblocked plans"
fi

log "Scan complete"
