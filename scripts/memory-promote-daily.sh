#!/bin/bash
# memory-promote-daily — Session → Working promotion
# Runs nightly at 11pm via PM2 cron.
# Scope: Steps 1–3 + Step 8 of memory-sync CLAUDE.md (session scan, promote to working, LibreChat import).
# Model: Sonnet (categorization judgment requires more than binary relevance scoring).
# Steps 4–7 (working → distilled, expiry) run in memory-sync-weekly on Mondays.

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/memory-promote-daily-$(date +%Y-%m-%d).log"

# Lock file — prevent overlapping runs
LOCK_FILE="$HOME/.claude/memory-promote-daily.lock"
STALE_MINUTES=30

if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( ($(date +%s) - $(stat -c %Y "$LOCK_FILE")) / 60 ))
    if [ "$LOCK_AGE" -gt "$STALE_MINUTES" ]; then
        echo "[$(date)] Removing stale lock (${LOCK_AGE}m old)" | tee -a "$LOG_FILE"
        rm -f "$LOCK_FILE"
    else
        echo "[$(date)] memory-promote-daily already running (lock age: ${LOCK_AGE}m). Skipping." | tee -a "$LOG_FILE"
        exit 0
    fi
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

echo "[$(date)] Starting memory-promote-daily..." | tee -a "$LOG_FILE"

cd ~/.claude/projects/memory-sync

echo "Run ONLY Steps 1, 2, 3, and 8 of the memory workflow described in CLAUDE.md. \
Focus on yesterday's and today's session transcripts. \
Step 1: scan session notes from the last 48 hours across all project .memsearch/memory/ directories. \
Step 2: promote durable chunks to working-tier notes in ~/.claude/memory/shared/ with correct frontmatter \
(tier: working, category: <see rules below>, created: today, expires: <see rules>, tags, source=memory-promote-daily). \
Category and expires rules for new notes: \
  - category: transient-finding  → expires: 90 days from today  (default for most findings) \
  - category: session-summary    → expires: 30 days from today  (use for session-level recap notes) \
  - category: decision-record    → expires: never               (use when a clear decision was made) \
  - category: design-document    → expires: never               (use for architecture / design notes) \
  - category: research-finding-permanent → expires: never       (use for knowledge that won't go stale) \
If a note already has a category: field, preserve it. When in doubt, use category: transient-finding. \
Step 3: import LibreChat memory if a fresh export is available. \
Step 8: log metrics (entries scanned, notes promoted, notes updated, errors). \
Do NOT execute Steps 4–7 (working review, distillation, expiry, dedup — those run in memory-sync-weekly on Mondays). \
If nothing durable was found in the last 48 hours, exit cleanly and log that result." | \
  timeout 900 claude -p \
  --model sonnet \
  --add-dir ~/.claude/memory \
  --dangerously-skip-permissions \
  >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

MATRIX="$HOME/scripts/send-matrix.sh"

if [ $EXIT_CODE -eq 0 ]; then
    PROMOTED=$(grep -c "promoted\|new working note\|written to" "$LOG_FILE" 2>/dev/null || echo 0)
    echo "[$(date)] memory-promote-daily completed. Approx promotions: $PROMOTED" | tee -a "$LOG_FILE"
    if [ "$PROMOTED" -gt 0 ]; then
        "$MATRIX" sysadmin "[memory-promote-daily] Complete: ~${PROMOTED} notes promoted to working tier." || true
    fi
elif [ $EXIT_CODE -eq 124 ]; then
    echo "[$(date)] memory-promote-daily timed out after 900s." | tee -a "$LOG_FILE"
    "$MATRIX" sysadmin "[memory-promote-daily] TIMEOUT: exceeded 900s — killed. Check $LOG_FILE" || true
else
    echo "[$(date)] memory-promote-daily failed with exit code $EXIT_CODE." | tee -a "$LOG_FILE"
    "$MATRIX" sysadmin "[memory-promote-daily] FAILED (exit $EXIT_CODE). Check $LOG_FILE" || true
fi
