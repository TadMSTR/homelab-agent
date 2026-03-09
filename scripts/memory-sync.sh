#!/bin/bash
# Memory Sync Agent — runs Claude Code in headless mode to distill durable knowledge
# Triggered by PM2 cron (see pm2/ecosystem.config.js.example)
#
# Prerequisites:
#   - Claude Code CLI installed with valid subscription
#   - Memory directories populated by agent sessions
#   - Context repo cloned locally
#   - (Optional) LibreChat memory export script at ~/.claude/scripts/export-librechat-memory.sh

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/memory-sync-$(date +%Y-%m-%d).log"

# Replace with your notification endpoint
NTFY_URL=""  # e.g., "https://ntfy.example.com/your-topic"

# Replace with your context repo path
CONTEXT_REPO="$HOME/repos/YOUR_CONTEXT_REPO"

# Replace with your memory-sync project directory
MEMORY_SYNC_PROJECT="$HOME/.claude/projects/memory-sync"

echo "[$(date)] Starting memory sync..." | tee -a "$LOG_FILE"

# (Optional) Export LibreChat memory before running the sync agent.
# Adapt this to your chat UI — this script should dump recent memory
# entries to ~/.claude/memory/chat-staging/
# if [ -f "$HOME/.claude/scripts/export-librechat-memory.sh" ]; then
#     "$HOME/.claude/scripts/export-librechat-memory.sh" >> "$LOG_FILE" 2>&1
# fi

cd "$MEMORY_SYNC_PROJECT"

# Run Claude Code in headless mode from the memory-sync project dir.
# Claude Code picks up CLAUDE.md from cwd project resolution.
# --add-dir grants access to memory dirs and context repo for writing.
# Pipe prompt via stdin (positional arg hangs without a TTY).
# 5-minute timeout prevents runaway sessions.
echo "Run the memory sync workflow as described in CLAUDE.md. Review the last 7 days of agent memory from both Claude Code (memsearch) and LibreChat (staging export) sources. Distill durable knowledge only." | \
  timeout 300 claude -p \
  --model haiku \
  --add-dir "$CONTEXT_REPO" \
  --add-dir "$HOME/.claude/memory" \
  --dangerously-skip-permissions \
  >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    # Count notes created by checking git status in the context repo
    cd "$CONTEXT_REPO"
    NOTE_COUNT=$(git diff --name-only HEAD~1 HEAD -- memory/distilled/ 2>/dev/null | wc -l)
    echo "[$(date)] Memory sync completed. Notes created: $NOTE_COUNT" | tee -a "$LOG_FILE"
    [ -n "$NTFY_URL" ] && curl -s -d "Memory sync completed — $NOTE_COUNT notes distilled" "$NTFY_URL" > /dev/null
else
    echo "[$(date)] Memory sync failed with exit code $EXIT_CODE." | tee -a "$LOG_FILE"
    [ -n "$NTFY_URL" ] && curl -s -d "Memory sync FAILED (exit $EXIT_CODE)" "$NTFY_URL" > /dev/null
fi

# Cleanup logs older than 30 days
find "$LOG_DIR" -name "memory-sync-*.log" -mtime +30 -delete
