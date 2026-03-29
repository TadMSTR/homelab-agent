# Memory Pipeline

The memory pipeline is a sequential orchestrator that runs nightly at 4 AM as a PM2 cron service. It chains three steps in order: `memory-sync` → `memsearch-compact` → `qmd-reindex`. Each step depends on the previous — if compact fails, reindex is skipped; if memory-sync fails, compact and reindex still run on existing data.

**Script:** `~/.claude/scripts/memory-pipeline.sh`  
**PM2 service:** `memory-pipeline` (cron: `0 4 * * *`)  
**Lock file:** `/tmp/memory-pipeline.lock` (flock-based, prevents overlapping runs)  
**Log:** `~/.local/share/logs/memory-pipeline.log`

## How It Works

```
memory-pipeline.sh (PM2 cron, 4 AM)
  │
  ├─ flock /tmp/memory-pipeline.lock  (abort if already running)
  │
  ├─ Step 1: memory-sync  [timeout: 1500s]
  │    │
  │    ├─ success → continue
  │    ├─ timeout (exit 124) → ntfy alert, log TIMED OUT, continue to Step 2
  │    └─ failure (other) → log FAILED, continue to Step 2
  │         (memory-sync failure is non-fatal — compact/reindex run on existing data)
  │
  ├─ Step 2: memsearch-compact  [no timeout]
  │    │
  │    ├─ success → continue
  │    └─ failure → log FAILED, exit 1  (qmd-reindex skipped)
  │
  └─ Step 3: qmd-reindex  [no timeout]
       ├─ success → pipeline complete
       └─ failure → log FAILED, exit 1
```

### Step 1: memory-sync

The most expensive step — runs an LLM-backed session consolidation (5–15 min typical, up to ~30 min with graph ingestion). The pipeline imposes a **1500-second (25-minute) wall-clock cap** via `timeout`.

If memory-sync **times out** (exit code 124):
- Logs: `--- memory-sync: TIMED OUT after 1500s ---`
- Fires an ntfy alert to `https://ntfy.glitch42.com/claudebox` with title `[memory-pipeline] memory-sync timeout`
- Continues to Step 2 with whatever data exists on disk

If memory-sync **fails** for any other reason:
- Logs: `--- memory-sync: FAILED (exit N) ---`
- Continues to Step 2 (no ntfy for non-timeout failures — use logs to investigate)

This non-fatal handling means a failing or slow memory-sync doesn't block the memsearch index and qmd from being refreshed. The session data that didn't get processed will be picked up on the next nightly run.

**The timeout was reduced from 1800s → 1500s** in the fault-tolerance build. The previous 30-minute cap was too generous — with graph ingestion (Step 5b) and graph entity dedup (Step 5c), a typical run now completes in 20–25 minutes. The tighter cap catches genuine hangs faster.

### Step 2: memsearch-compact

Runs `~/.claude/scripts/memsearch-compact.sh`. Sets `CALLED_FROM_PIPELINE=1` before calling so the compact script knows it's running unattended (some scripts use this to skip interactive prompts). Fatal — if compact fails, reindex is skipped.

### Step 3: qmd-reindex

Runs `~/scripts/qmd-reindex.sh`. Rebuilds the qmd semantic search index over the current state of markdown files. Fatal — logged and exited if it fails. A failed reindex means the previous index remains in use (stale but functional) until the next successful pipeline run.

## memory-sync: Steps 5b and 5c

These steps run inside memory-sync itself, not in the pipeline script. They're documented here because they were added in the fault-tolerance build and both affect pipeline timing.

### Step 5b: Graph Ingestion (Graphiti)

After distilling working notes to permanent records, memory-sync ingests touched notes into the Neo4j knowledge graph via the Graphiti MCP. Uses a content hash manifest at `~/.claude/memory/graph-ingested.json` to skip unchanged notes.

Ingest scope:
- Notes created or updated in this run (always ingest)
- Notes with no manifest entry (never ingested before)
- Notes whose content hash differs from the manifest (changed outside this run)

If Graphiti is unavailable, this step is logged and skipped — it never blocks the rest of memory-sync.

### Step 5c: Graph Entity Deduplication (cap: 10 candidates)

After graph ingestion, memory-sync queries Graphiti for near-duplicate nodes caused by LLM name variation — e.g., `grafana` vs `Grafana`, `neo4j` vs `Neo4j`. 

Process:
1. Query `search_nodes` for each entity type: Service, Host, Network, Agent
2. Normalize names (lowercase, strip trailing "s", strip " dashboard"/" container"/" service")
3. Group nodes with matching normalized names — any group with >1 node is a merge candidate
4. For each candidate (up to 10 total per run):
   - Choose canonical form: prefer Title Case; tie-break on most facts
   - Fetch facts on non-canonical nodes via `search_memory_facts`
   - Call `delete_entity_edge` on each edge UUID from the non-canonical node
5. Defer any candidates beyond 10 to the next run

Edges are deleted, not reparented. Future ingestion will organically rebuild canonical node relationships because memory-sync always writes entity names in Title Case.

This step is capped at 10 candidates to control Anthropic API cost per run. A typical nightly run processes 0–3 candidates.

## Configuration

**PM2 ecosystem config:** `~/scripts/ecosystem-memory.config.js` (or inline in the main ecosystem config)

The pipeline uses `flock -n` — non-blocking. If the lock is already held (previous run still active), the new invocation logs `"already running, exiting"` and exits cleanly. This prevents two simultaneous memory-sync sessions from racing on the same files.

**Timeout implementation:** Uses `bash timeout <seconds> bash <script>`. Exit code 124 is the POSIX timeout signal — any other non-zero exit is a script failure. Only `memory-sync` has a timeout configured; the other two steps have no wall-clock limit.

## Observability

**Logs:** `~/.local/share/logs/memory-pipeline.log` — timestamped entries for every step start/end/fail/timeout. Tailed via `pm2 logs memory-pipeline`.

**ntfy alerts:** Only on memory-sync timeout (1500s exceeded). Other failures are log-only. If you want to catch non-timeout failures, grep the log for `FAILED`.

**PM2 status:** `pm2 list` shows last exit code and uptime. Because the pipeline exits after each run (not always-on), PM2 shows it as `stopped` between 4 AM runs — this is normal.

## Gotchas and Lessons Learned

**`stopped` in PM2 is normal.** The pipeline exits on completion. PM2 will show `status: stopped` with a non-zero restart count. This is expected for cron-style PM2 services. Check `pm2 logs memory-pipeline` for actual run outcomes rather than PM2 status.

**memory-sync timeout vs failure.** The ntfy alert only fires on timeout (exit 124). A memory-sync crash (out of memory, Python exception, network error) produces `FAILED` in the log but no notification. Check the log if the daily graph ingestion counts in the health report look wrong.

**Lock file left after a crash.** If the pipeline process is killed (`kill -9`) mid-run, the lock file at `/tmp/memory-pipeline.lock` may be left behind. Flock on a file descriptor — not the file itself — so the lock is released when the process dies and the fd is closed. The `.lock` file itself is cleaned up by the `trap 'rm -f "$LOCK"' EXIT` handler, but a hard kill may skip the trap. If the pipeline won't start, check `lsof /tmp/memory-pipeline.lock` — if nothing holds it, delete it manually.

**Step 5c cost is bounded.** Each dedup candidate involves at least one `search_memory_facts` call and potentially multiple `delete_entity_edge` calls — each costs Anthropic API tokens. The 10-candidate cap is intentional. If you see more than 10 candidates deferred repeatedly, consider running a manual dedup session or increasing the cap temporarily.

**memsearch-compact must succeed for reindex to run.** If compact fails (e.g., memsearch process down), qmd will not be reindexed that night. The previous qmd index stays active — searches work but may be stale. Investigate with `pm2 logs memory-pipeline` and re-run manually: `bash ~/.claude/scripts/memory-pipeline.sh`.

## Manual Re-Run

To run the pipeline outside the 4 AM schedule:

```bash
# Full pipeline
bash ~/.claude/scripts/memory-pipeline.sh

# Individual steps
bash ~/.claude/scripts/memory-sync.sh
bash ~/.claude/scripts/memsearch-compact.sh
bash ~/scripts/qmd-reindex.sh
```

The lock prevents concurrent runs — if 4 AM fires while you're running manually, the cron invocation will exit immediately.

---

## Related Docs

- [memory-sync](memory-sync.md) — the LLM-backed session consolidation step (Steps 1–8)
- [memsearch](memsearch.md) — semantic search index being compacted in Step 2
- [Graphiti](graphiti.md) — Neo4j knowledge graph fed by Step 5b ingestion
- [Architecture overview](../../README.md) — memory tier model context
