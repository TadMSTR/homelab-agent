# Forge — Memory Migration (May 2026)

**Completed:** 2026-05-30
**Snapshot:** `pre-memory-migration-20260529` (in `/.snapshots/`)
**Build:** `forge-memory-migration-2026-05`

## What Was Built

Migrated agent memory from claudebox (reference host) to forge (primary host going forward).
Backfilled working-tier notes that accumulated on claudebox from April 2026 onward, ported
the NFS archiving pipeline, and populated the memory metadata index which had silently been
empty since deployment.

## Phases Completed

### Phase 1 — Btrfs Snapshot

Snapshot taken before any writes: `pre-memory-migration-20260529` at `/.snapshots/`.

### Phase 2–3 — Memory Backfill

Backfilled 432 shared working-tier notes and 48 claudebox agent memories via rsync with
`--ignore-existing` (forge-originated notes not overwritten).

| Source | Files copied |
|--------|-------------|
| claudebox `~/.claude/memory/shared/` | 432 notes |
| claudebox agent dirs (research, dev, security, panel-dev, writer) | 48 notes |
| Destination on forge | `~/.claude/memory/shared/` and `~/.claude/memory/shared/claudebox-agents/` |

The `claudebox-agents/` subdirectory keeps claudebox agent notes searchable without
conflating them with forge-resident agent directories.

### Phase 4 — Distilled Tier Sync

`design-records` Gitea repo pulled to sync the distilled tier (latest claudebox-committed notes).

### Phase 5 — Reindex

- `memsearch-watch` (polling, 5-min interval) indexed the new notes into Milvus.
- `qmd-refresh.sh` triggered to update the qmd semantic index.

### Phases 7–12 — NFS Archive Mirror

Created NFS archive directories on Atlas:

```
/mnt/atlas/forge/memory-archive/
  current/     # latest state of durable/distilled notes
  changes/     # versioned daily backups of overwritten files
```

Ported four scripts from claudebox to `host-forge-scripts/scripts/`:

| Script | Purpose |
|--------|---------|
| `send-matrix.sh` | Matrix notification helper |
| `memory-archive-mirror.sh` | Rsync durable/distilled notes to NFS |
| `memory-metadata-index.py` | Full-rebuild SQLite indexer for `.metadata.db` |
| `memory-os-sync.py` | OpenSearch sync (port patched: 9200 → 9202 for forge) |

Registered `memory-archive-mirror` as PM2 cron (ID 28, `30 2 * * *`) on forge.
Disabled `memory-archive-mirror` on claudebox (PM2 ID 36, stopped + saved).

Smoke test passed: 3 durable files mirrored to NFS, Matrix notification received.

### Discovery: .metadata.db Was Empty

`memory-metadata-mcp` had been running on forge for 47 hours but `.metadata.db` was 0 bytes.
Root cause: `memory-metadata-index.py` was never ported from claudebox — the MCP server
started successfully without it (no hard dependency at startup) but the indexer was never
running to populate the database.

**Fix applied in this build:** ported `memory-metadata-index.py` and ran a full index pass:

```
memory-metadata-index.py --full
```

Result: 1,696 notes indexed into `.metadata.db`. Verified with:

```sql
SELECT tier, COUNT(*) FROM notes GROUP BY tier;
```

## What's Deferred

**Phase 6 — Graphiti batch ingestion** — re-ingesting the 432 backfilled notes into
the Graphiti knowledge graph. Requires `memory-sync.py --step graph-ingest`. Deferred
to a follow-on plan.

**Memory promotion pipeline** — completed as `forge-memory-pipeline-2026-05` (2026-05-30).
All four PM2 jobs now running on forge; claudebox promotion jobs stopped.

## Services Modified

| Service | Change |
|---------|--------|
| `memory-archive-mirror` (PM2 ID 28, forge) | New — cron 02:30 daily |
| `memory-archive-mirror` (PM2 ID 36, claudebox) | Stopped and disabled |
| `memory-metadata-mcp` (forge) | Now has a populated `.metadata.db` (was 0 bytes) |
