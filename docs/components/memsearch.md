# memsearch

memsearch is the semantic memory indexing and search library for forge. It ingests agent memory
files into [Milvus](memory-stack.md) (vector store) and [OpenSearch](memory-stack.md) (BM25
full-text), then combines both signals with a local neural reranker to rank results. Two PM2
processes consume it: `memsearch-watch` keeps the index current, and `memsearch-mcp` exposes
search and index-refresh tools to agents.

- **Venv:** `/opt/venvs/memsearch/`
- **CLI:** `/opt/venvs/memsearch/bin/memsearch`
- **Reranker model:** `Alibaba-NLP/gte-reranker-modernbert-base` (sentence-transformers, local)

## memsearch-watch (PM2 id 10)

`memsearch-watch` is the index daemon. It runs `memsearch index` on a fixed 5-minute interval
across all memory directories, then sleeps and repeats.

**Why polling, not watchdog:** An earlier version used `memsearch watch` (inotify-based). It had a
threading bug: `watchdog` fires per-file debounce timers in separate threads, and when multiple
files change simultaneously (common during agent memory writes) concurrent `loop.run_until_complete()`
calls raise `RuntimeError: This event loop is already running`. The watch process stayed alive
but silently skipped the conflicting files. The polling approach avoids this entirely — memsearch
skips files that haven't changed (content-hash checked), so full scans are fast.

**Script:** `~/scripts/memsearch-watch.sh`

```
Interval: 300 s
Logs:     ~/logs/memsearch/watch-<timestamp>.log (30-day retention, chmod 640)
```

### Directories indexed

| Directory | Tier |
|-----------|------|
| `~/.claude/memory/` | working |
| `~/.claude/projects/*/.memsearch/memory/` | session (per-project plugin dirs) |

The session-tier glob (`~/.claude/projects/*/.memsearch/memory/`) covers all projects where the
Claude Code MemSearch plugin has created a local index directory. Directories that don't exist
are skipped silently.

## Reranker

`sentence-transformers` is installed in the memsearch venv alongside the base library. The
`Alibaba-NLP/gte-reranker-modernbert-base` model runs locally on the GPU (Minisforum MS-A2 has an
integrated RDNA3). No external API calls for reranking.

To confirm the reranker is active:

```bash
/opt/venvs/memsearch/bin/python3 -c "from memsearch.config import resolve_config; c = resolve_config(); print(c.reranker.model)"
```

## Configuration

memsearch reads from `~/.memsearch/config.toml` (or the location set by `MEMSEARCH_CONFIG`).
Forge runtime configuration:

| Section | Key | Value | Purpose |
|---------|-----|-------|---------|
| `[milvus]` | `uri` | `http://127.0.0.1:19530` | Milvus vector store |
| `[milvus]` | `collection` | `memsearch_chunks` | Collection name |
| `[embedding]` | `provider` | `ollama` | Embedding backend |
| `[embedding]` | `model` | `bge-m3` | Embedding model |
| `[embedding]` | `base_url` | `http://127.0.0.1:11435` | Ollama queue proxy |
| `[embedding]` | `batch_size` | `16` | Batch embedding size |
| `[reranker]` | `model` | `Alibaba-NLP/gte-reranker-modernbert-base` | Local reranker |
| `[chunking]` | `max_chunk_size` | `1500` | Chars per chunk |
| `[chunking]` | `overlap_lines` | `2` | Overlap between chunks |
| `[compact]` | `llm_provider` | `anthropic` | LLM for compaction |
| `[compact]` | `llm_model` | `claude-sonnet-4-6` | Compaction model |

## Dependencies

| Service | Purpose |
|---------|---------|
| `milvus` (port 19530) | Vector store — required for search and index |
| `ollama-queue-proxy` (port 11435) | Serialized embedding inference |
| `opensearch` (port 9202) | BM25 full-text index (used by qmd and memory-search-mcp) |

## Operations

```bash
# Check memsearch-watch is running
pm2 status memsearch-watch

# Tail the current log
tail -f ~/logs/memsearch/watch-$(ls -t ~/logs/memsearch/ | head -1)

# Manually trigger a full index run
/opt/venvs/memsearch/bin/memsearch index ~/.claude/memory/

# Run a test search from the CLI
/opt/venvs/memsearch/bin/memsearch search "grafana dashboard setup"

# Restart memsearch-watch (e.g., after config change)
pm2 restart memsearch-watch
```

If the watch daemon reports index errors, check that Milvus and the Ollama queue proxy are healthy
first. memsearch will fail if embeddings can't be generated.

## Related Docs

- [memsearch-mcp.md](memsearch-mcp.md) — MCP server wrapping memsearch (agent tool surface)
- [memsearch-summarize.md](memsearch-summarize.md) — session transcript summarizer
- [memory-services.md](memory-services.md) — overview of memory layer PM2 services
- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch storage backends
- [ollama.md](ollama.md) — embedding inference via Ollama queue proxy
