# memsearch

memsearch is the semantic memory indexing and search library for forge. It ingests agent memory
files into [Milvus](memory-stack.md), which provides both vector similarity and BM25 full-text
search (Milvus 2.5+ native hybrid). A local neural reranker combines both signals to rank
results. Two PM2 processes consume it: `memsearch-watch` keeps the index current, and
`memsearch-mcp` exposes search and index-refresh tools to agents.

> **Not to be confused with** [memory-search-mcp](memory-services.md), which is a separate
> full-text search service backed by [OpenSearch](memory-stack.md). memsearch does not use
> OpenSearch.

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
| `[llm.providers.ollama]` | `type` | `openai-compatible` | Provider type for local LLM calls |
| `[llm.providers.ollama]` | `base_url` | `http://127.0.0.1:11435/v1` | OQP OpenAI-compat endpoint (`/v1` suffix required) |
| `[llm.providers.ollama]` | `api_key` | (from forge.env) | OQP API key for LLM provider calls |
| `[plugins.claude-code.summarize]` | `enabled` | `true` | Enable session transcript summarizer |
| `[plugins.claude-code.summarize]` | `provider` | `ollama` | Routes to `[llm.providers.ollama]` |
| `[plugins.claude-code.summarize]` | `model` | `memsearch-summarize` | Custom Ollama modelfile (see below) |
| `[prompts]` | `summarize` | `~/.memsearch/prompts/summarize-local.txt` | Custom system prompt for summarize plugin |

## Summarize plugin

The `plugins.claude-code.summarize` plugin ingests raw session transcripts from `.memsearch/spool/` and compresses them into bullet summaries, then writes the result back so later searches hit the condensed form rather than raw tool output.

**Model:** `memsearch-summarize` — a custom Ollama modelfile built on `qwen3:14b` with the `/no_think` template suffix (disables chain-of-thought output), `temperature 0.1`, and `num_predict 400`. Keeps summaries tight and deterministic.

**Routing:** LLM calls go through `[llm.providers.ollama]` which points at OQP (`http://127.0.0.1:11435/v1`, OpenAI-compat endpoint). This gives the summarize plugin the same priority queuing and concurrency caps as other OQP consumers. Embedding calls (`[embedding]`) continue to use the Ollama native API on the same OQP port (`http://127.0.0.1:11435`, no `/v1`).

**Custom prompt:** `~/.memsearch/prompts/summarize-local.txt` overrides the default system prompt. Edit this file to tune summary style without touching the memsearch library.

```bash
# Check the active summarize model
/opt/venvs/memsearch/bin/python3 -c "
from memsearch.config import resolve_config
c = resolve_config()
print(c.plugins['claude-code']['summarize'])
"
```

## Dependencies

| Service | Purpose |
|---------|---------|
| `milvus` (port 19530) | Vector store + BM25 full-text — required for search and index |
| `ollama-queue-proxy` (port 11435) | Serialized embedding inference |

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
- [ollama.md](../ai-search/ollama.md) — embedding inference via Ollama queue proxy
