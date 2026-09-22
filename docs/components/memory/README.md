# Memory — Persistent Agent Memory & Knowledge Graph

The memory system gives agents recall across sessions. Notes flow through three tiers (session → working → distilled), indexed by four search backends that serve different query patterns.

**Start with [memory-architecture.md](memory-architecture.md)** for the full system overview with diagrams.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [memory-architecture.md](memory-architecture.md) | Three-tier memory system overview | — |
| [memory-stack.md](memory-stack.md) | Milvus (stopped) + OpenSearch (live) Docker stack | 19530 (free), 9202 |
| [memory-services.md](memory-services.md) | PM2 indexing services and promotion pipeline | — |
| [scribe.md](scribe.md) | Transcript extractor + digest writer, replaced memsearch-summarize 2026-09-17 | — (hourly cron) |
| [memsearch.md](memsearch.md) | Hybrid vector+BM25 search library, retired 2026-09-17 | — |
| [memsearch-mcp.md](memsearch-mcp.md) | memsearch MCP server, retired 2026-09-17 | — |
| [memsearch-summarize.md](memsearch-summarize.md) | Session transcript summarizer, retired 2026-09-17 | — |
| [memory-expire.md](memory-expire.md) | Expired note eviction cron | — (cron) |
| [memory-compact-qc.md](memory-compact-qc.md) | Weekly QC on Ollama compact output | — (cron) |
| [graphiti.md](graphiti.md) | Temporal knowledge graph (Neo4j), retired 2026-08-05 | — |

## Query Paths

| Need | MCP Server | Backend |
|------|-----------|---------|
| Semantic / fuzzy recall (incl. session digests) | qmd | Own in-process `llama.cpp` embedder |
| Keyword / phrase search | memory-fulltext-mcp | OpenSearch (BM25) |
| Filter by tag, date, tier | memory-metadata-mcp | SQLite |
