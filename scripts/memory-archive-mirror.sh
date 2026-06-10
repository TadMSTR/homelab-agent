#!/bin/bash
# Mirror durable + distilled memory to NFS with versioned backups of changes.
# - current/  → latest state of all durable/distilled notes
# - changes/YYYY-MM-DD/  → prior versions of anything overwritten that day
# - No --delete: source-side deletions are preserved in the archive (append-only)
#
# PM2: memory-archive-mirror, cron 02:30 daily

set -euo pipefail
umask 0077

LOG="$HOME/.claude/logs/memory-archive-mirror.log"
mkdir -p "$(dirname "$LOG")"
exec >> "$LOG" 2>&1

ts()    { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo "[$(ts)] INFO  $*"; }
warn()  { echo "[$(ts)] WARN  $*"; }
error() { echo "[$(ts)] ERROR $*"; }

SRC="$HOME/.claude/memory/"
DEST="/mnt/atlas/forge/memory-archive/current/"
BACKUP_DIR="/mnt/atlas/forge/memory-archive/changes/$(date +%Y-%m-%d)/"
DB="$HOME/.claude/memory/.metadata.db"

info "memory-archive-mirror starting"

# Preflight: NFS mount available?
if ! mountpoint -q /mnt/atlas/forge; then
  warn "NFS /mnt/atlas/forge unavailable — skipping run"
  "$HOME/scripts/send-matrix.sh" sysadmin "[memory-archive-mirror] NFS unavailable, run skipped at $(ts)" || true
  exit 0
fi

# Preflight: metadata DB available?
if [[ ! -f "$DB" ]]; then
  warn "Metadata DB not found at $DB — skipping run"
  "$HOME/scripts/send-matrix.sh" sysadmin "[memory-archive-mirror] Metadata DB missing, run skipped at $(ts)" || true
  exit 0
fi

# Build file list from SQLite: durable and distilled tier notes
DURABLE_LIST=$(mktemp)
trap 'rm -f "$DURABLE_LIST"' EXIT

sqlite3 "$DB" \
  "SELECT path FROM notes WHERE tier IN ('durable','distilled') OR (tier='working' AND category IN ('decision-record','design-document','research-finding-permanent','competitive-snapshot'))" \
  | sed "s|^$HOME/.claude/memory/||" > "$DURABLE_LIST"

FILE_COUNT=$(wc -l < "$DURABLE_LIST")

if [[ "$FILE_COUNT" -eq 0 ]]; then
  warn "Empty file list from DB ($DB) — skipping run to avoid truncating mirror"
  "$HOME/scripts/send-matrix.sh" sysadmin "[memory-archive-mirror] Empty file list from DB, run skipped at $(ts)" || true
  exit 0
fi

info "Mirroring $FILE_COUNT durable/distilled/durable-category files to NFS"

mkdir -p "$DEST" "$BACKUP_DIR"

rsync -av \
  --backup --backup-dir="$BACKUP_DIR" \
  --files-from="$DURABLE_LIST" \
  "$SRC" "$DEST" \
  | tail -3

info "memory-archive-mirror complete ($FILE_COUNT files, backup dir: $BACKUP_DIR)"
"$HOME/scripts/send-matrix.sh" sysadmin "[memory-archive-mirror] $FILE_COUNT files mirrored to NFS (durable/distilled + durable-category working notes)" || true
