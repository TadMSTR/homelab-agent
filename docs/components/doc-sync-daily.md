# doc-sync-daily

Scheduled job that fetches, converts, and caches upstream documentation for homelab services.
Saves chunked markdown files to `~/.claude/memory/docs/<service>/` where memsearch indexes
them for agent retrieval.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `doc-sync-daily` |
| Type | cron |
| Schedule | `0 3 * * *` (daily, 03:00) |
| Interpreter | `/opt/venvs/doc-sync/bin/python3` |
| Script | `~/scripts/doc-sync.py` |
| Port | — (no listener) |

## How It Works

1. Reads service list from `~/docs/doc-sync.yml`
2. Fetches upstream docs for each configured service (URLs, formats)
3. Converts to markdown and chunks into sized segments (150–4000 chars)
4. Writes chunks to `~/.claude/memory/docs/<service>/`
5. Updates state in `~/docs/doc-sync-state.json` to avoid re-fetching unchanged docs
6. memsearch-watch picks up new/changed files on its next polling cycle

## Configuration

| File | Purpose |
|------|---------|
| `~/docs/doc-sync.yml` | Service list and source URLs |
| `~/docs/doc-sync-state.json` | Fetch state / last-modified tracking |
| `~/docs/doc-sync.log` | Run log |

## Dependencies

- memsearch venv at `/opt/venvs/doc-sync/` — Python runtime
- Ollama queue proxy at `127.0.0.1:11435` — embedding (via memsearch)
- Internet access — fetches upstream documentation

## Operations

```bash
pm2 logs doc-sync-daily --lines 50   # last run output
pm2 restart doc-sync-daily            # trigger manual run
```

Output lands in `~/.claude/memory/docs/`. Check `doc-sync-state.json` for per-service
fetch timestamps. Chunks have a 90-day expiration — stale entries are not refreshed
if the upstream source is unreachable.

## Related Docs

- [memory-services.md](memory-services.md) — memory indexing pipeline
- [memsearch.md](memsearch.md) — memsearch library that indexes the output
