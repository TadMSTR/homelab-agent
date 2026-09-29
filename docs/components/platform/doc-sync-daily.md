# doc-sync-daily

Scheduled job that fetches, converts, and caches upstream documentation for homelab services.
Saves chunked markdown files to `~/.claude/memory/docs/<service>/`, indexed for agent retrieval
by qmd's `docs` collection (hourly `qmd-refresh.sh`) since the 2026-09-17 memsearch retirement
— see [memsearch.md](../memory/memsearch.md#retirement).

As of ADR-0006 (2026-07-07), this script's `sync_service()` logic is shared with
[doc-cache-mcp](../mcp-servers/doc-cache-mcp.md): the cron below drives an unattended sweep
of every configured service, while `doc-cache-mcp`'s `doc_cache_sync` tool lets the research
agent trigger the same fetch/convert/chunk path on demand for a single service. Both share
the same `flock` on the state file, so they never race writes, and both enforce the same
source-URL allowlist at fetch time (see Configuration).

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
6. The hourly `qmd-refresh.sh` cron picks up new/changed files on its next run and re-embeds
   them into the `docs` collection. (Before the 2026-09-17 memsearch retirement, this step was
   `memsearch-watch-fast` on a 60s poll — see [memsearch.md](../memory/memsearch.md#retirement).
   **`~/scripts/doc-sync.py` itself still shells out to `memsearch` internally and that call
   has been failing nightly against the now-dead Milvus backend** — not fixed here, flagged to
   sysadmin separately; don't read this step as currently working end-to-end even though the
   qmd-side indexing it feeds is fine.)

## Configuration

| File | Purpose |
|------|---------|
| `~/docs/doc-sync.yml` | Service list and source URLs (symlink to `host-forge-scripts/scripts/doc-sync.yml`; also the file `doc-cache-mcp`'s `doc_cache_add_service` tool edits) |
| `~/docs/doc-sync-state.json` | Fetch state / last-modified tracking |
| `~/docs/doc-sync.log` | Run log |
| `host-forge-scripts/doc-cache-allowlist.yml` | Source-URL allowlist — every fetch (cron or `doc-cache-mcp`) is validated against this, including each redirect hop, before it is followed |

## Dependencies

- `/opt/venvs/doc-sync/` — Python runtime (dependency-only venv, no self-package)
- qmd's `docs` collection (`~/.config/qmd/index.yml`), refreshed hourly by `qmd-refresh.sh` —
  the live indexing path since the 2026-09-17 memsearch retirement; qmd's own embedding model
  runs locally and does not go through the Ollama queue proxy
- Internet access — fetches upstream documentation
- `host-forge-scripts/doc-cache-allowlist.yml` — default-deny source-URL allowlist enforced at fetch time (ADR-0006)

## Operations

```bash
pm2 logs doc-sync-daily --lines 50   # last run output
pm2 restart doc-sync-daily            # trigger manual run
```

Output lands in `~/.claude/memory/docs/`. Check `doc-sync-state.json` for per-service
fetch timestamps. Chunks have a 90-day expiration — stale entries are not refreshed
if the upstream source is unreachable.

## Related Docs

- [doc-cache-mcp.md](../mcp-servers/doc-cache-mcp.md) — MCP server sharing this script's core sync logic; supersedes the old research agent system-ops doc-sync grant (ADR-0006)
- [memory-services.md](../memory/memory-services.md) — memory indexing pipeline
- [memsearch.md](../memory/memsearch.md) — retired 2026-09-17; qmd's `docs` collection replaced
  it as the indexer for this script's output
