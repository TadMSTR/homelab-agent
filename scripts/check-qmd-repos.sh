#!/bin/bash
# check-qmd-repos.sh — Add new repos to the QMD index automatically
#
# Scans REPOS_DIR for git repos not yet listed in the QMD config file.
# Auto-adds each new repo with a default file pattern and triggers a reindex.
# Sends a push notification when repos are added.
#
# Triggered by PM2 cron (see pm2/ecosystem.config.js.example).
# Can also be run manually: ./check-qmd-repos.sh

REPOS_DIR="$HOME/repos/personal"
QMD_CONFIG="$HOME/.config/qmd/index.yml"
REINDEX_SCRIPT="$(dirname "$0")/qmd-reindex.sh"
NTFY_URL=""  # e.g., "https://ntfy.example.com/your-topic"
LOG="$HOME/.local/share/logs/check-qmd-repos-$(date +%Y-%m-%d).log"

mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

if [ ! -f "$QMD_CONFIG" ]; then
    log "ERROR: QMD config not found at $QMD_CONFIG"
    exit 1
fi

# Extract paths already indexed
indexed_paths=$(grep '^\s*path:' "$QMD_CONFIG" | awk '{print $2}')

# Find repos not yet indexed
to_add=()
for dir in "$REPOS_DIR"/*/; do
    dir="${dir%/}"
    [ -d "$dir/.git" ] || continue  # skip non-git dirs
    echo "$indexed_paths" | grep -qF "$dir" && continue
    to_add+=("$(basename "$dir")")
done

if [ ${#to_add[@]} -eq 0 ]; then
    log "All repos indexed. Nothing to do."
    exit 0
fi

# Auto-add all new repos to QMD config
added=()
for name in "${to_add[@]}"; do
    path="$REPOS_DIR/$name"
    log "Auto-adding: $name"

    printf '\n  %s:\n    path: %s\n    pattern: "**/*.{md,ts,js,json,sh,yml,yaml}"\n    context:\n      "": "Auto-added: %s"\n' \
        "$name" "$path" "$name" >> "$QMD_CONFIG"

    added+=("$name")
done

# Trigger reindex to pick up new collections
log "Running reindex for ${#added[@]} new collection(s)..."
if bash "$REINDEX_SCRIPT" >> "$LOG" 2>&1; then
    log "Reindex OK"
else
    log "WARNING: Reindex failed — check log"
fi

# Notify
msg="QMD: auto-added ${#added[@]} repo(s): $(echo "${added[*]}" | tr ' ' ', ')"
log "$msg"
[ -n "$NTFY_URL" ] && curl -s \
    -H "Title: QMD: Repo index updated" \
    -H "Tags: books" \
    -H "Priority: default" \
    -d "$msg" \
    "$NTFY_URL" > /dev/null

# Cleanup logs older than 30 days
find "$(dirname "$LOG")" -name "check-qmd-repos-*.log" -mtime +30 -delete
