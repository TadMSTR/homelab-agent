# memsearch-mcp (retired 2026-09-17)

memsearch-mcp was the FastMCP server wrapping the [memsearch](memsearch.md) semantic memory
search library. It exposed hybrid vector+BM25+reranker search and index-refresh tools
(`search_memory`, `index_memory`) to forge agents over streamable-http MCP transport at
`http://127.0.0.1:8493/mcp`.

## Retirement

Retired 2026-09-17 alongside the rest of the memsearch stack — see
[memsearch.md](memsearch.md#retirement) for the full cutover record
(`memory-consolidation-2026-09` part 3, vikunja#863).

- PM2 process stopped and deleted; port 8493 freed.
- Removed from all 6 agent manifests. This needed an explicit pass — a running scoped-mcp
  process caches its tool inventory at startup, so `search_memory` stayed registered and
  failing at call time rather than disappearing on its own until each manifest was edited.
- The `archival-search` skill, which used memsearch-mcp as its primary search backend, was
  rewritten to query [qmd](../ai-search/ollama.md) directly instead.

Agents that need semantic recall across memory notes should query **qmd** (port 8181,
`session-digests` and related collections) — see
[memory-architecture.md](memory-architecture.md) for the current query-path table.

## Related Docs

- [memsearch.md](memsearch.md) — the library this server wrapped, retired the same day
- [memory-architecture.md](memory-architecture.md) — current memory system map and query paths
- [scoped-mcp.md](../agent/scoped-mcp.md) — manifest structure and agent tool surfaces
