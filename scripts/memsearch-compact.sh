#!/bin/bash
# Memsearch compact — daily consolidation of session memory files.
# Runs after memory-sync (4:30 AM) to compact today's and yesterday's session notes.
# Scoped to individual session files to avoid re-processing the entire index.

set -euo pipefail

# Ollama embedding via forge RTX 2000 Ada
export OLLAMA_HOST="https://ollama.helmforge.me"

# Load ANTHROPIC_API_KEY if not already set (needed for compact LLM calls)
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    _key=$(grep -m1 '^ANTHROPIC_API_KEY=' "$HOME/.secrets/forge.env" 2>/dev/null | cut -d= -f2-)
    [ -n "$_key" ] && export ANTHROPIC_API_KEY="$_key"
fi

PIPELINE_LOCK=/tmp/memory-pipeline.lock

# Abort immediately if the memory-pipeline orchestrator is running (standalone guard only)
if [ -f "$PIPELINE_LOCK" ] && [ -z "${CALLED_FROM_PIPELINE:-}" ]; then
    echo "$(date): memsearch-compact aborted — memory-pipeline lock held, retry manually" >> "$HOME/.local/share/logs/memsearch-compact.log"
    exit 0
fi

MEMSEARCH_CMD="/opt/venvs/memsearch/bin/memsearch"
command -v "$MEMSEARCH_CMD" >/dev/null 2>&1 || { echo "memsearch not found"; exit 1; }

# Compact summaries go here — under ~/.claude/memory/ so memsearch-watch indexes them automatically.
COMPACT_OUT="$HOME/.claude/memory/shared/compact"
mkdir -p "$COMPACT_OUT"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d yesterday +%Y-%m-%d)

# Prepend frontmatter to a compact output file if it lacks it.
# memsearch compact writes plain markdown with no frontmatter; the lint check rejects these.
inject_frontmatter() {
    local file="$1" date_str="$2"
    [ -f "$file" ] || return 0
    [[ "$(head -1 "$file")" == "---" ]] && return 0
    local expires
    expires=$(date -d "$date_str +30 days" +%Y-%m-%d)
    local tmpfile
    tmpfile=$(mktemp)
    printf -- '---\ntier: working\ncategory: session-summary\ncreated: %s\nsource: memsearch-compact\nexpires: %s\n---\n\n' \
        "$date_str" "$expires" > "$tmpfile"
    cat "$file" >> "$tmpfile"
    mv "$tmpfile" "$file"
    echo "  Injected frontmatter into $(basename "$file")"
}

# Compact session files across all project memsearch directories
for project_dir in "$HOME"/.claude/projects/*/.memsearch/memory; do
  [ -d "$project_dir" ] || continue

  for datefile in "$TODAY" "$YESTERDAY"; do
    file="$project_dir/$datefile.md"
    [ -f "$file" ] || continue

    echo "[$(date '+%H:%M:%S')] Compacting: $file"
    $MEMSEARCH_CMD compact --source "$file" --output-dir "$COMPACT_OUT" 2>&1 \
      || { echo "  Warning: compact failed for $file"
           ~/scripts/send-matrix.sh sysadmin "memsearch compact failed: $(basename "$file")" > /dev/null || true; }
    inject_frontmatter "$COMPACT_OUT/memory/$datefile.md" "$datefile"
  done
done

# Compact global session store
GLOBAL_SESSION="$HOME/.memsearch/memory"
if [ -d "$GLOBAL_SESSION" ]; then
  for datefile in "$TODAY" "$YESTERDAY"; do
    file="$GLOBAL_SESSION/$datefile.md"
    [ -f "$file" ] || continue
    echo "[$(date '+%H:%M:%S')] Compacting global session: $file"
    $MEMSEARCH_CMD compact --source "$file" --output-dir "$COMPACT_OUT" 2>&1 \
      || { echo "  Warning: compact failed for $file"
           ~/scripts/send-matrix.sh sysadmin "memsearch compact failed: $(basename "$file")" > /dev/null || true; }
    inject_frontmatter "$COMPACT_OUT/memory/$datefile.md" "$datefile"
  done
fi

echo "[$(date '+%H:%M:%S')] Compact complete."
