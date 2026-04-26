# Memory Lifecycle

The memory lifecycle system governs how agent memory notes are categorized, retained, indexed, and archived. It adds two new query layers over the memory corpus — a SQLite metadata index and an OpenSearch full-text engine — and provides structured MCP access to both. Durable notes are mirrored to NFS and seeded into a permanent Gitea repo. The scope boundary is strict: SearXNG and LibreChat agent configs are untouched; memory excerpts never surface in shared search results.

## Category Field

Every memory note carries a `category:` frontmatter field that determines its retention policy. There are six categories across two groups:

| Category | Expires | When to use |
|----------|---------|-------------|
| `transient-finding` | 90 days | Default for session findings, debugging notes, one-off research |
| `session-summary` | 30 days | End-of-session or mid-session summaries |
| `decision-record` | Never | Architecture decisions, tradeoffs chosen, non-obvious constraints |
| `design-document` | Never | System design docs, specs, plans that remain reference material |
| `research-finding-permanent` | Never | Benchmark results, evaluations, discoveries with lasting value |
| `competitive-snapshot` | Never | Tool/vendor comparisons, market state at a point in time |

**Expiring categories** are eligible for deletion after their TTL elapses. `memory-sync-weekly` handles expiry as part of its 90-day cleanup pass.

**Durable categories** never expire. Notes with durable categories are mirrored to the NFS archive on the backup host and seeded into the `design-records` Gitea repo (`ted/design-records`) for permanent retention outside the local filesystem.

**Inference rule for writers:** if Ted asked for a writeup, evaluation, or design → durable category. If recording what happened in a session → `transient-finding` or `session-summary`.

The backfill (run once at build time) assigned categories to 2818 existing notes using a classification pass. Notes without a `category:` field default to `transient-finding` at query time.

---

## Index Architecture

The memory corpus is queryable through two independent indexes:

```
~/.claude/memory/
│
├── .metadata.db          ← SQLite WAL-mode index (metadata only, no bodies)
│                            2819 notes indexed: category, tier, tags, created,
│                            expires, source, path
│
└── [all memory notes]    ← Full text indexed by OpenSearch 2.19.1
                             on 127.0.0.1:9200 (memory-search-net only)
                             Index: claude-memory
                             Document: path, title, body excerpt (first 2KB),
                                       category, tier, tags, created
```

**SQLite metadata index** (`~/.claude/memory/.metadata.db`) — lightweight, always-on, host-local. Designed for structured filtered queries: "list all decision-record notes from the last 30 days," "count notes by category," "find all notes tagged with 'auth'." No body content stored — path pointers only.

**OpenSearch full-text index** — full body excerpt (first 2KB per note) indexed for keyword and phrase search. Supports relevance ranking across the entire corpus. Access is scoped to the personal-agent (see MCP Tool Surface below). Container runs on a dedicated single-member Docker network (`memory-search-net`) — isolated from the shared `claudebox-net`.

**Sync daemon:** `memory-os-sync` (PM2, always-on) batch-syncs memory notes to OpenSearch on a 30-second interval in 50-document batches. It maintains a cursor to avoid full re-scans; changed or new notes are detected by mtime and pushed incrementally. A forced full sync runs nightly via `memory-pipeline`.

---

## MCP Tool Surface

Two FastMCP servers provide structured access to the memory indexes:

### memory-metadata-mcp

**Port:** 8490 (`127.0.0.1`)  
**Scope:** All agents (global manifest)  
**Index:** SQLite `.metadata.db`

Provides filtered, structured queries over note metadata. No body content returned — returns paths, titles, frontmatter fields.

| Tool | What It Does |
|------|-------------|
| `list_notes` | Filter by category, tier, tag, date range, source agent. Returns paths + metadata. |
| `count_by` | Group note counts by a field (category, tier, source) with optional filters. |
| `get_note_meta` | Fetch full frontmatter for a specific note by path. |

**Primary use case:** inventory queries ("how many decision-record notes are there?"), audit passes (doc-health), and targeted lookups before reading a note's body with `homelab-ops__read_file`.

### memory-search-mcp

**Port:** 8491 (`127.0.0.1`)  
**Scope:** Personal-agent ONLY (scoped manifest at `~/.claude/manifests/personal-agent.yml`)  
**Index:** OpenSearch `claude-memory`

Provides full-text body search over the entire memory corpus. Returns path, title, category, tier, and an excerpt of the matching passage.

| Tool | What It Does |
|------|-------------|
| `search_memory` | Free-text query over body excerpts. Returns ranked results with snippet highlighting. |

**Scope rationale:** body excerpts could in principle contain sensitive content (internal hostnames, partially-captured configs). Scoping to personal-agent keeps full-text search out of LibreChat agents and other consumers that share the global manifest.

**Note on existing tools:** `memsearch` (session-tier, Milvus-backed) and `qmd` (working/distilled tiers, BM25 + vector) continue to serve their tiers. `archival-search` skill runs all three backends in a single pass and merges results with tier labels — recommended default over calling any one directly.

---

## PM2 Services

Two new PM2 services manage the OpenSearch index and NFS archive:

| Service | Schedule | What It Does |
|---------|----------|-------------|
| `memory-os-sync` | always-on | Batch-syncs memory notes to OpenSearch (30s intervals, 50-doc batches, cursor-based incremental) |
| `memory-archive-mirror` | 02:30 AM daily | Append-versioned NFS rsync of durable notes to NFS backup host (`memory-archive/{current,changes}`) |

**memory-archive-mirror** runs with `umask 0077` — archive directories are 0700 (not world-readable). The mirror uses rsync in append-then-diff mode: current durable notes are always present in `current/`, and daily diffs land in `changes/<YYYY-MM-DD>/` for point-in-time recovery.

---

## Durable Storage

Notes with a durable category (`decision-record`, `design-document`, `research-finding-permanent`, `competitive-snapshot`) are retained in two places beyond the working-tier memory files:

**NFS archive** — Read-write NFS mount on the backup host (`memory-archive/`). Survives agent host disk failure. Managed by `memory-archive-mirror`.

**design-records Gitea repo** — `ted/design-records` on the local Gitea instance. Seeded with all durable notes at build time; updated nightly by `repo-sync-nightly`. Provides versioned history, diff visibility, and a path for future cross-instance sharing.

---

## Scope Boundary

Existing SearXNG and LibreChat configurations are **completely unchanged** by this build. Memory note excerpts are indexed only in the `claude-memory` OpenSearch index and in the SQLite metadata DB — neither of these is connected to SearXNG or LibreChat's search pipeline. A user searching via LibreChat or SearXNG will never see agent memory excerpts in results.

This is a deliberate design decision maintained from v1. Agents with access to `memory-search-mcp` can search memory bodies; no other consumer does.

---

## Security Posture

**OpenSearch network isolation (M1 — medium, fixed):** The OpenSearch container is on a dedicated single-member `memory-search-net` Docker network. It is **not** on the shared agent network. This prevents the 35+ containers on that network (crawl4ai, SearXNG, LibreChat, n8n, matrix-synapse, etc.) from reaching OpenSearch unauthenticated.

`memory-search-mcp` reaches OpenSearch via host loopback (`127.0.0.1:9200`) — this path is always available regardless of network membership. No other path exists.

**Container hardening:** `memory-metadata-mcp` and `memory-search-mcp` run with `cap_drop: ALL`, `no-new-privileges: true`, non-root user (1000:1000).

**Archive permissions:** NFS archive directories are 0700 (`ted:ted`). `memory-archive-mirror.sh` runs with `umask 0077` to enforce this on newly created `changes/<date>/` subdirectories.

**OpenSearch image:** SHA-pinned to digest `sha256:72fe2fc8…e89a4` — not tag-only.

**No-fix accepted items:**
- Body excerpts (first 2KB per note) sent to OpenSearch could contain secrets if a future note captures one. Current corpus spot-checked as doc-cache content only. Revisit if token-bearing notes start landing. M1 fix materially shrinks read blast radius.
- OpenSearch security plugin remains disabled — acceptable on a single-member isolated network. Revisit only if cross-host or untrusted-container access is added.

---

## Integration with Existing Memory System

This build adds layers; it does not replace anything.

```
Session tier      memsearch (Milvus)    ← unchanged
Working tier      qmd (BM25 + vector)   ← unchanged
Distilled tier    qmd + prime-directive ← unchanged

All tiers         SQLite metadata DB    ← NEW: structured filtered queries (all agents)
All tiers         OpenSearch full-text  ← NEW: body keyword search (personal-agent only)
Durable only      NFS + design-records  ← NEW: off-host retention for durable categories
```

`archival-search` skill remains the recommended default — it queries memsearch + qmd and merges results. Add `memory-metadata-mcp` calls when you need category/tag/date filtering; add `memory-search-mcp` when you need body keyword search and you're in the personal-agent context.

The `memory-sync-weekly` expiry step now reads `category:` to determine which notes are eligible — expiring notes past their TTL are pruned; durable notes are never marked for expiry.

---

## Related Docs

- [memory-pipeline](memory-pipeline.md) — nightly consolidation orchestrator
- [memory-sync](memory-sync.md) — LLM-backed session consolidation (Steps 1–8)
- [memsearch](memsearch.md) — session-tier semantic search
- [graphiti](graphiti.md) — Neo4j temporal knowledge graph
- [repo-sync-nightly](repo-sync-nightly.md) — nightly repo sync that feeds design-records
