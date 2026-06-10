#!/usr/bin/env python3
"""
memory-expire — evict memory notes whose expires date has passed.

Queries .metadata.db for notes where expires < today, moves them to
~/.claude/memory/.expired/YYYY-MM-DD/ (preserving relative path), then
triggers memory-metadata-index --prune to remove stale DB rows.

memsearch-watch drops evicted files from Milvus on its next 60s cycle.

PM2: memory-expire, cron 0 3 * * * (after archive-mirror at 02:30)
"""

import logging
import shutil
import sqlite3
import subprocess
import sys
from datetime import date
from pathlib import Path

MEMORY_DIR  = Path.home() / ".claude/memory"
DB_PATH     = MEMORY_DIR / ".metadata.db"
EXPIRED_DIR = MEMORY_DIR / ".expired"
LOG_FILE    = Path.home() / ".claude/logs/memory-expire.log"
SEND_MATRIX = Path.home() / "scripts/send-matrix.sh"
INDEX_SCRIPT = Path.home() / "scripts/memory-metadata-index.py"

LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [memory-expire] %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


def send_matrix(room: str, msg: str) -> None:
    if SEND_MATRIX.exists():
        subprocess.run([str(SEND_MATRIX), room, msg], check=False, timeout=10)


def main() -> None:
    today = date.today().isoformat()
    log.info("starting — today=%s", today)

    if not DB_PATH.exists():
        log.warning("metadata DB not found at %s — skipping", DB_PATH)
        send_matrix("sysadmin", "[memory-expire] Metadata DB missing, skipped")
        sys.exit(0)

    con = sqlite3.connect(str(DB_PATH))
    try:
        rows = con.execute(
            "SELECT path, tier, category, expires FROM notes "
            "WHERE expires IS NOT NULL AND expires < ?",
            (today,),
        ).fetchall()
    finally:
        con.close()

    if not rows:
        log.info("no expired notes found")
        return

    bucket = EXPIRED_DIR / today
    bucket.mkdir(parents=True, exist_ok=True)

    evicted: list[str] = []
    errors:  list[str] = []

    for path_str, tier, category, expires in rows:
        src = Path(path_str)
        if not src.exists():
            log.info("already gone: %s", path_str)
            continue

        try:
            rel = src.relative_to(MEMORY_DIR)
        except ValueError:
            rel = Path(src.name)

        dest = bucket / rel
        dest.parent.mkdir(parents=True, exist_ok=True)

        try:
            shutil.move(str(src), str(dest))
            log.info("evicted: %s (tier=%s category=%s expires=%s)", rel, tier, category, expires)
            evicted.append(str(rel))
        except OSError as e:
            log.error("failed to move %s: %s", path_str, e)
            errors.append(str(rel))

    # Prune stale DB rows so metadata index reflects evictions immediately
    if INDEX_SCRIPT.exists():
        result = subprocess.run(
            [sys.executable, str(INDEX_SCRIPT), "--prune"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            log.warning("prune returned %d: %s", result.returncode, result.stderr.strip())
        else:
            log.info("DB pruned")

    log.info("done — evicted=%d errors=%d", len(evicted), len(errors))

    msg = f"[memory-expire] {len(evicted)} note(s) expired → .expired/{today}"
    if errors:
        msg += f" | {len(errors)} error(s) — check log"
    send_matrix("sysadmin", msg)


if __name__ == "__main__":
    main()
