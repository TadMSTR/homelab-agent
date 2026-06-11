# Memory Services

PM2-managed services that form the agent memory layer on top of the
[memory-stack](memory-stack.md) Docker containers (Milvus + OpenSearch). Two groups:
**indexing and search** (always-on) and **promotion pipeline** (scheduled).

## memsearch-watch

Polls all memory directories every 300 seconds and re-indexes changed files into Milvus.
Uses content-hash checking so unchanged files are skipped — full scans are fast.

**Script:** `~/scripts/memsearch-watch.sh`

Directories indexed:

| Directory | Tier |
|-----------|------|
| `~/.claude/memory/` | working |
| `~/.claude/templates/` | templates |
| `~/.claude/projects/*/.memsearch/memory/` | session (per-project) |

Logs to `~/logs/memsearch/watch-<timestamp>.log` (30-day retention).

Note: an earlier version used `memsearch watch` (inotify-based). It had a threading bug where
concurrent file changes caused silent indexing failures. Replaced with polling in May 2026.
See [memsearch.md](memsearch.md) for full details.

## memsearch-mcp

FastMCP server exposing hybrid vector+BM25+reranker memory search to forge agents over
streamable-http MCP transport.

```bash
/opt/venvs/memsearch/bin/python3 ~/repos/personal/memsearch-mcp/server.py
```

- **Endpoint:** `http://127.0.0.1:8493/mcp`
- **Transport:** streamable-http

See [memsearch-mcp.md](memsearch-mcp.md) for tool surface, agent access matrix, and operations.

## qmd

Semantic + keyword search MCP server over ~9 000 markdown documents across 40+
collections (docs cache, component docs, build reports, agent memory, etc.). Supports
BM25 (lexical), vector (semantic), and HyDE (hypothetical document) sub-queries.

```bash
qmd mcp --http --port 8181 --host 127.0.0.1
```

- **Endpoint:** `http://127.0.0.1:8181`
- **Collections:** see `qmd status` for the full list and per-collection doc counts

## memory-metadata-mcp

Read-only MCP server exposing a SQLite metadata index over `~/.claude/memory/` notes.
Provides `list_notes`, `get_note_metadata`, and `count_by` tools for structured queries
by category, tier, tag, or date — without reading note bodies.

```bash
/home/ted/repos/personal/memory-metadata-mcp/server.py
```

- **Endpoint:** `http://127.0.0.1:8490`
- **Transport:** streamable-http

## memory-search-mcp

Full-text search MCP over memory notes via OpenSearch. Returns body excerpts alongside
metadata, enabling queries that require matching note content rather than just frontmatter.
Scope: personal-agent use only (not in the global scoped-mcp manifest).

```bash
/home/ted/repos/personal/memory-search-mcp/server.py
```

- **Endpoint:** `http://127.0.0.1:8491`
- **Backend:** OpenSearch at `127.0.0.1:9202`
- **Transport:** streamable-http

## memsearch-summarize

FastMCP server and background daemon that summarizes raw session transcripts in memsearch
spool directories via the Anthropic API. Replaces verbose logs with 3–6 bullet summaries.

```bash
/opt/venvs/memsearch/bin/python3 ~/repos/gitea/host-forge-scripts/scripts/memsearch-summarize.py
```

- **Endpoint:** `http://127.0.0.1:8494/mcp`
- **Transport:** streamable-http
- **Poll interval:** 10 seconds

See [memsearch-summarize.md](memsearch-summarize.md) for tools, configuration, and operations.

## Promotion Pipeline (scheduled)

Five cron jobs + two always-on daemons drive the memory tier lifecycle on forge.
Scripts live in `host-forge-scripts/scripts/`, symlinked to `~/scripts/`.

```mermaid
flowchart LR
    session["**Session tier**\n.memsearch/spool/\n(per-project)"]
    working["**Working tier**\n~/.claude/memory/"]
    distilled["**Distilled tier**\n~/.claude/memory/\n(distilled/)"]
    archive["**NFS archive**\natlas <nas-ip>"]

    session -- "memory-promote-daily\n23:00 daily" --> working
    working -- "memory-sync-weekly\nMon 07:00" --> distilled
    working -- "memory-archive-mirror\n02:30 daily" --> archive
    distilled -- "memory-archive-mirror\n02:30 daily" --> archive
```

| PM2 name | Type | Schedule | Purpose |
|----------|------|----------|---------|
| `memory-os-sync` | always-on | — | Syncs `.metadata.db` → OpenSearch every 30s |
| `memory-promote-daily` | cron | `0 23 * * *` | Steps 1–3, 8 of memory-sync: session scan, promote to working, LibreChat import |
| `memory-sync-weekly` | cron | `0 7 * * 1` | Steps 4–8: working → distilled, expiry, dedup, metrics |
| `memory-pipeline` | cron | `0 4 * * *` | memsearch-compact + qmd-refresh |
| `memory-archive-mirror` | cron | `30 2 * * *` | rsync durable notes to NFS (atlas) with versioned change backups |
| `qmd-refresh` | cron | `0 * * * *` | `qmd update` + `qmd embed` — keeps agent-memory collection current hourly |

The promotion jobs drive headless Claude Code sessions via `~/.claude/projects/memory-sync/CLAUDE.md`.
Matrix notifications go to `#sysadmin` on forge's Synapse homeserver.

`memory-archive-mirror` logs to `~/.claude/logs/memory-archive-mirror.log`. NFS target:
`<nas-ip>:/mnt/storage/forge` (atlas). Append-only: source-side deletions are preserved in the
archive under `changes/YYYY-MM-DD/`.

---

## Dependency Chain

```mermaid
flowchart TD
    files["**~/.claude/memory/**\nmarkdown files"]

    files --> summarize["memsearch-summarize\nalways-on :8494"]
    summarize <--> anthropic["Anthropic API\nclaude-sonnet-4-6"]
    summarize --> files

    files --> watch["memsearch-watch\npoll 300s"]
    watch --> milvus[("Milvus\nvectors :19530")]
    milvus --> memsearch_mcp["memsearch-mcp\n:8493"]
    milvus --> qmd_svc["qmd\n:8181"]

    files --> qmd_refresh["qmd-refresh\nhourly cron"]
    qmd_refresh --> qmd_svc

    files --> meta_mcp["memory-metadata-mcp\n:8490"]
    meta_mcp --> sqlite[("SQLite\n.metadata.db")]
    sqlite --> os_sync["memory-os-sync\nalways-on 30s"]
    os_sync --> opensearch[("OpenSearch\n:9202")]
    opensearch --> search_mcp["memory-search-mcp\n:8491"]

    files --> archive["memory-archive-mirror\n02:30 daily"]
    archive --> nfs[("NFS — atlas\n<nas-ip>")]

    subgraph "MCP servers (agents query these)"
        memsearch_mcp
        qmd_svc
        meta_mcp
        search_mcp
    end

    subgraph "Storage backends"
        milvus
        sqlite
        opensearch
        nfs
    end
```

All always-on services depend on the [memory-stack](memory-stack.md) containers being healthy.
If Milvus or OpenSearch is down, the respective MCP server will fail silently on search
but will not crash.

## Related Docs

- [memory-architecture.md](memory-architecture.md) — full system map: tiers, indices, and Graphiti
- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch storage backends
- [memsearch.md](memsearch.md) — memsearch library, polling watch daemon, reranker
- [memsearch-mcp.md](memsearch-mcp.md) — MCP server wrapping memsearch
- [memsearch-summarize.md](memsearch-summarize.md) — session transcript summarizer
- [graphiti.md](graphiti.md) — knowledge graph (relational, temporal — separate from flat memory)
