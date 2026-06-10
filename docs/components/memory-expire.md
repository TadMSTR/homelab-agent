# memory-expire

Scheduled job that evicts memory notes whose `expires` date has passed. Moves expired
files to a dated archive directory and prunes the metadata database.

- **Script:** `~/scripts/memory-expire.py`
- **Interpreter:** `python3`
- **Schedule:** PM2 cron, daily at 03:00 (`0 3 * * *`) — runs after archive-mirror (02:30)
- **Log:** `~/.claude/logs/memory-expire.log`
- **No listening port** — runs as a batch job

## How It Works

1. Queries `~/.claude/memory/.metadata.db` for notes where `expires < today`
2. Moves matched files to `~/.claude/memory/.expired/YYYY-MM-DD/` preserving relative paths
3. Runs `memory-metadata-index.py --prune` to remove stale DB rows
4. Sends summary to `#sysadmin` Matrix room via `send-matrix.sh`
5. memsearch-watch drops evicted files from Milvus on its next 60-second polling cycle

## Configuration

| Setting | Value |
|---------|-------|
| Memory dir | `~/.claude/memory/` |
| Metadata DB | `~/.claude/memory/.metadata.db` |
| Expired dir | `~/.claude/memory/.expired/` |
| Log file | `~/.claude/logs/memory-expire.log` |
| Index script | `~/scripts/memory-metadata-index.py` |
| Alert script | `~/scripts/send-matrix.sh` |
| Alert room | `#sysadmin` |

## Dependencies

- **memory-metadata-index.py** — SQLite indexer, provides the `--prune` flag
- **memsearch-watch** — picks up file deletions and updates Milvus index
- **send-matrix.sh** — Matrix notifications
- **.metadata.db** — SQLite database with note metadata including `expires` field

## Operations

```bash
# Check last run
pm2 show memory-expire

# View log
tail -20 ~/.claude/logs/memory-expire.log

# Trigger manual run
pm2 restart memory-expire

# Check expired archive
ls ~/.claude/memory/.expired/
```

## Related Docs

- [memory-services.md](memory-services.md) — memory pipeline overview
- [memory-architecture.md](memory-architecture.md) — three-tier memory design
