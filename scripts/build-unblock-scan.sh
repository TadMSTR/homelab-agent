#!/bin/bash
set -euo pipefail

LOG="$HOME/logs/build-unblock-scan.log"
PLANS_DIR="$HOME/.claude/comms/artifacts/build-plans"
MATRIX_MCP_URL="http://127.0.0.1:8487/mcp"

mkdir -p "$HOME/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

matrix_notify() {
    # SECURITY[resolved]: use jq to construct JSON payload — prevents injection from unescaped message content.
    # Audit: 2026-05-29/forge-build-workflow-infra-2026-05.
    local msg="$1"
    local payload
    payload=$(jq -n --arg msg "$msg" \
        '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"send_matrix_message","arguments":{"room_name":"agents","message":$msg}},"id":1}')
    curl -s -X POST "$MATRIX_MCP_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        > /dev/null 2>&1 || true
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
