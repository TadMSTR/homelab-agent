#!/bin/bash
# memory-sync-weekly — Working → Distilled promotion + expiry
# Runs Mondays at 7am via PM2 cron.
# Scope: Steps 4–8 of memory-sync CLAUDE.md (working review, distillation, expiry, dedup, metrics).
# Model: Opus (higher judgment bar for permanent distillation decisions).
# Steps 1–3 (session → working) run in memory-promote-daily nightly.

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/memory-sync-weekly-$(date +%Y-%m-%d).log"

# Lock file — prevent overlapping runs
LOCK_FILE="$HOME/.claude/memory-sync-weekly.lock"
STALE_MINUTES=60

if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( ($(date +%s) - $(stat -c %Y "$LOCK_FILE")) / 60 ))
    if [ "$LOCK_AGE" -gt "$STALE_MINUTES" ]; then
        echo "[$(date)] Removing stale lock (${LOCK_AGE}m old)" | tee -a "$LOG_FILE"
        rm -f "$LOCK_FILE"
    else
        echo "[$(date)] memory-sync-weekly already running (lock age: ${LOCK_AGE}m). Skipping." | tee -a "$LOG_FILE"
        exit 0
    fi
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

echo "[$(date)] Starting memory-sync-weekly..." | tee -a "$LOG_FILE"

cd ~/.claude/projects/memory-sync

echo "Run ONLY Steps 4, 5, 5b, 5c, 6, 7, and 8 of the memory workflow described in CLAUDE.md. \
Step 4: review all working notes 14+ days old — assess for distillation readiness, currency, or deletion. \
Step 5: promote qualifying notes to distilled tier in prime-directive/memory/distilled/, git commit and push. \
Step 5b: ingest touched notes to the Graphiti knowledge graph. \
Step 5c: deduplicate near-duplicate graph nodes (cap 10 candidates). \
Step 6: merge topical duplicate working notes. \
Step 7: expire working notes based on their category field (check frontmatter): \
  - category: transient-finding  → expire after 90 days (existing behavior) \
  - category: session-summary    → expire after 30 days \
  - category: decision-record, design-document, research-finding-permanent, competitive-snapshot → NEVER expire; skip entirely \
  - tier: durable (any category) → NEVER expire; skip entirely \
  - no category field present    → treat as transient-finding (90-day expiry) \
  For any durable-category note not modified in 180+ days: log a NOTICE (do NOT delete or warn). \
  Append expired notes to expiry-log.md before deleting. \
Step 8: output metrics (working notes reviewed, distilled, expired by category, skipped-durable, deduped, graph ingested, errors). \
Do NOT execute Steps 1–3 (session scanning — that runs in memory-promote-daily nightly)." | \
  timeout 1800 claude -p \
  --model opus \
  --add-dir ~/.claude/memory \
  --dangerously-skip-permissions \
  >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

MATRIX="$HOME/scripts/send-matrix.sh"

if [ $EXIT_CODE -eq 0 ]; then
    DISTILLED=$(grep -c "distilled\|promoted to distilled\|prime-directive" "$LOG_FILE" 2>/dev/null || echo 0)
    EXPIRED=$(grep -c "expired\|deleted\|expiry-log" "$LOG_FILE" 2>/dev/null || echo 0)
    echo "[$(date)] memory-sync-weekly completed. Distilled: ~$DISTILLED, Expired: ~$EXPIRED" | tee -a "$LOG_FILE"
    "$MATRIX" sysadmin "[memory-sync-weekly] Complete: ~${DISTILLED} distilled, ~${EXPIRED} expired." || true
elif [ $EXIT_CODE -eq 124 ]; then
    echo "[$(date)] memory-sync-weekly timed out after 1800s." | tee -a "$LOG_FILE"
    "$MATRIX" sysadmin "[memory-sync-weekly] TIMEOUT: exceeded 1800s — killed. Check $LOG_FILE" || true
else
    echo "[$(date)] memory-sync-weekly failed with exit code $EXIT_CODE." | tee -a "$LOG_FILE"
    "$MATRIX" sysadmin "[memory-sync-weekly] FAILED (exit $EXIT_CODE). Check $LOG_FILE" || true
fi
