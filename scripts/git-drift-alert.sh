#!/bin/bash
# git-drift-alert.sh — detect uncommitted changes in tracked platform repos
# and notify via Matrix. Re-alerts only when drift changes (new files, resolved,
# or different content). Suppresses repeat alerts for unchanged dirty state.
#
# Runs via PM2 cron. State stored in ~/.local/state/git-drift/.
set -euo pipefail

LOG="$HOME/logs/git-drift-alert.log"
STATE_DIR="$HOME/.local/state/git-drift"
mkdir -p "$HOME/logs" "$STATE_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

# Repos to monitor — path:label pairs
declare -A REPOS=(
  ["$HOME/repos/gitea/agent-platform-agents"]="agent-platform/agents"
  ["$HOME/.claude/skills"]="agent-platform/skills"
  ["$HOME/repos/gitea/host-forge-scripts"]="host-forge/scripts"
  ["$HOME/repos/gitea/host-forge-build-reports"]="host-forge/build-reports"
  ["$HOME/repos/gitea/agent-platform-knowledge-base"]="agent-platform/kb"
  ["$HOME/repos/gitea/host-forge-knowledge-base"]="host-forge/docs"
)

DIRTY_REPOS=()
ALERT_BODY=""
ANY_NEW_DRIFT=false

for repo_path in "${!REPOS[@]}"; do
  label="${REPOS[$repo_path]}"
  slug="${label//\//-}"
  state_file="$STATE_DIR/$slug.hash"

  if [[ ! -d "$repo_path/.git" ]]; then
    continue
  fi

  status_output=$(git -C "$repo_path" status --short 2>/dev/null || true)

  if [[ -z "$status_output" ]]; then
    # Repo is clean — clear any stored state
    rm -f "$state_file"
    continue
  fi

  # Repo is dirty — check if this is new or changed drift
  current_hash=$(echo "$status_output" | sha256sum | cut -d' ' -f1)
  stored_hash=""
  [[ -f "$state_file" ]] && stored_hash=$(cat "$state_file")

  if [[ "$current_hash" != "$stored_hash" ]]; then
    ANY_NEW_DRIFT=true
    echo "$current_hash" > "$state_file"
    log "New/changed drift in $label"
  fi

  DIRTY_REPOS+=("$label")
  ALERT_BODY+="$label:\n$status_output\n\n"
done

if [[ ${#DIRTY_REPOS[@]} -eq 0 ]]; then
  log "All repos clean"
  exit 0
fi

if [[ "$ANY_NEW_DRIFT" == "false" ]]; then
  log "Drift unchanged since last alert (${#DIRTY_REPOS[@]} repos) — suppressing"
  exit 0
fi

COUNT=${#DIRTY_REPOS[@]}
log "Alerting: $COUNT repo(s) with new/changed drift"

MSG="Git drift detected ($COUNT repo(s) with uncommitted changes):

${ALERT_BODY}Check and commit, or note as in-progress."

/home/ted/scripts/send-matrix.sh agents "$MSG"
