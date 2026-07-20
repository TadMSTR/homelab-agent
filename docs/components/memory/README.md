# Memory — Persistent Agent Memory & Knowledge Graph

The memory system gives agents recall across sessions. Notes flow through three tiers (session → working → distilled), indexed by four search backends that serve different query patterns.

**Start with [memory-architecture.md](memory-architecture.md)** for the full system overview with diagrams.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [memory-architecture.md](memory-architecture.md) | Three-tier memory system overview | — |
| [memory-stack.md](memory-stack.md) | Milvus + OpenSearch Docker stack | 19530, 9202 |
| [memory-services.md](memory-services.md) | PM2 indexing services and promotion pipeline | — |
| [memsearch.md](memsearch.md) | Hybrid vector+BM25 search library | — |
| [memsearch-mcp.md](memsearch-mcp.md) | memsearch MCP server | 8493 |
| [memsearch-summarize.md](memsearch-summarize.md) | Session transcript summarizer | 8494 |
| [memory-expire.md](memory-expire.md) | Expired note eviction cron | — (cron) |
| [memory-compact-qc.md](memory-compact-qc.md) | Weekly QC on Ollama compact output | — (cron) |
| [graphiti.md](graphiti.md) | Temporal knowledge graph (Neo4j) | 8000 |

## Query Paths

| Need | MCP Server | Backend |
|------|-----------|---------|
| Semantic / fuzzy recall | memsearch-mcp | Milvus (vector + BM25 + reranker) |
| Keyword / phrase search | memory-search-mcp | OpenSearch (BM25) |
| Filter by tag, date, tier | memory-metadata-mcp | SQLite |
| Entity relationships, temporal facts | graphiti-mcp | Neo4j |
