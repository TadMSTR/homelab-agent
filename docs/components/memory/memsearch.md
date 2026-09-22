# memsearch (retired 2026-09-17)

memsearch was forge's semantic memory indexing and search library. It ingested agent memory
files into Milvus, which provided both vector similarity and BM25 full-text search (Milvus
2.5+ native hybrid), and used a local neural reranker to combine both signals. Three PM2
processes consumed it: `memsearch-watch-fast` and `memsearch-watch-templates` kept the index
current, and `memsearch-mcp` exposed search and index-refresh tools to agents.

## Retirement

Retired 2026-09-17, part 3 of the `memory-consolidation-2026-09` programme (vikunja#861,
this part #863) — see the phase doc,
`host-forge-knowledge-base/phases/memory-consolidation-2026-09-p3-memsearch-retirement.md`.
Not an outage; a deliberate cutover.

What happened:

- `memsearch-watch-fast`, `memsearch-watch-templates`, `memsearch-mcp`, and
  `memsearch-summarize` (see [memsearch-summarize.md](memsearch-summarize.md)) — all four PM2
  processes stopped and deleted.
- The Milvus compose project (3 containers) stopped. Data deliberately **preserved** —
  `/opt/appdata/memsearch/` and the `milvus-minio` volume are both intact, so rollback is a
  restart, not a re-embed. See [memory-stack.md](memory-stack.md).
- The `memsearch-mcp` module removed from all 6 agent manifests.
- The Claude Code plugin, marketplace, and hook set deregistered (this took two passes — the
  first left `~/.claude/settings.json`'s declarative plugin keys in place, which
  re-materialized a working hook set on the next session; both keys were then removed).
- `archival-search` rewritten to source all memory tiers from qmd directly, closing vikunja#853.

Reclaimed 2,102 MiB VRAM (reranker + `bge-m3`) and freed ports 19530 and 8493.

**What replaced it:** [qmd](../ai-search/ollama.md) (port 8181) now backs semantic recall
across every memory tier, including session history via its `session-digests` collection —
[scribe](scribe.md) writes those digests on the hourly cron. See
[memory-architecture.md](memory-architecture.md) for the current query paths.

The fork repo `~/repos/personal/memsearch` is untouched on disk; only the marketplace
integration was removed.

## What it was

- **Venv:** `/opt/venvs/memsearch/`
- **Reranker model:** `Alibaba-NLP/gte-reranker-modernbert-base` (sentence-transformers,
  local, GPU)
- **Backend:** Milvus, collection `memsearch_chunks`, `http://127.0.0.1:19530`
- **Embedding:** `bge-m3` via the Ollama queue proxy (`http://127.0.0.1:11435`)
- **Watch daemons:** `memsearch-watch-fast` (60s poll, working + session tiers),
  `memsearch-watch-templates` (event-driven `inotifywait`, templates tier) — split from a
  single `memsearch-watch` service in July 2026

## Related Docs

- [memsearch-mcp.md](memsearch-mcp.md) — the MCP server that wrapped this library, retired the same day
- [memsearch-summarize.md](memsearch-summarize.md) — the summarizer component, retired the same day, replaced by [scribe](scribe.md)
- [memory-architecture.md](memory-architecture.md) — current memory system map
- [memory-stack.md](memory-stack.md) — Milvus (stopped, data preserved) + OpenSearch (still live)
- [scribe.md](scribe.md) — the replacement for session digest/summary generation
