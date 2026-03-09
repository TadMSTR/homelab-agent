#!/bin/bash
# qmd Reindex — pull latest repos and regenerate embeddings
# Triggered by PM2 cron (see pm2/ecosystem.config.js.example)

LOG="$HOME/.local/share/logs/qmd-reindex-$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Starting qmd reindex..."

if qmd update --pull >> "$LOG" 2>&1; then
    log "Git pull OK"
else
    log "WARNING: qmd update --pull had errors (some repos may have failed)"
fi

if qmd embed >> "$LOG" 2>&1; then
    log "Embed OK"
else
    log "ERROR: qmd embed failed"
    # Replace with your notification endpoint (ntfy, Gotify, Pushover, etc.)
    # curl -s -H "Priority: high" -d "qmd reindex FAILED" "https://YOUR_NTFY_SERVER/YOUR_TOPIC" > /dev/null
    exit 1
fi

# Cleanup logs older than 30 days
find "$(dirname "$LOG")" -name "qmd-reindex-*.log" -mtime +30 -delete

log "qmd reindex complete"
