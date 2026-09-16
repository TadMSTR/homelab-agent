# memsearch

memsearch is the semantic memory indexing and search library for forge. It ingests agent memory
files into [Milvus](memory-stack.md), which provides both vector similarity and BM25 full-text
search (Milvus 2.5+ native hybrid). A local neural reranker combines both signals to rank
results. Three PM2 processes consume it: `memsearch-watch-fast` and `memsearch-watch-templates`
keep the index current (see below), and `memsearch-mcp` exposes search and index-refresh
tools to agents.

> **Not to be confused with** [memory-fulltext-mcp](memory-services.md#memory-fulltext-mcp)
> (renamed from `memory-search-mcp` on 2026-07-23), which is a separate full-text search
> service backed by [OpenSearch](memory-stack.md). memsearch does not use OpenSearch.

- **Venv:** `/opt/venvs/memsearch/`
- **CLI:** `/opt/venvs/memsearch/bin/memsearch`
- **Reranker model:** `Alibaba-NLP/gte-reranker-modernbert-base` (sentence-transformers, local)

## memsearch-watch-fast and memsearch-watch-templates

The index daemon was split into two PM2 processes on 2026-07-20. Full detail (scripts,
directories indexed, logs) lives in [memory-services.md](memory-services.md); summary here:

- **`memsearch-watch-fast`** — polls the working (`~/.claude/memory/`) and session
  (`~/.claude/projects/*/.memsearch/memory/`) directories every 60 seconds. These
  directories change constantly during active sessions, so polling stays cheap thanks to
  content-hash change detection.
- **`memsearch-watch-templates`** — event-driven (`inotifywait`) watcher for
  `~/.claude/templates/`, debounced 30 seconds. Templates change rarely, so an
  event-driven watcher is more appropriate than polling.

**History:** the original single `memsearch-watch` service polled all three directories on
a fixed 5-minute interval — itself a replacement for an even earlier `memsearch watch`
(inotify-based) version with a threading bug: `watchdog` fires per-file debounce timers in
separate threads, and when multiple files changed simultaneously (common during agent
memory writes) concurrent `loop.run_until_complete()` calls raised
`RuntimeError: This event loop is already running`. The watch process stayed alive but
silently skipped the conflicting files. Polling avoided that bug entirely (memsearch skips
unchanged files via content-hash check, so full scans stayed fast), but a single 5-minute
interval was slower than ideal for the fast-changing tiers and unnecessarily frequent for
templates — hence the July 2026 split into two purpose-fit processes.

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
| `[llm]` | `provider` | `openai` | Default library-level LLM provider (e.g. `compact`) |
| `[llm]` | `model` | `mistral-medium-latest` | Default model |
| `[llm]` | `base_url` | `https://api.mistral.ai/v1` | Default OpenAI-compatible endpoint |
| `[llm.providers.ollama]` | `type` | `openai-compatible` | Provider type for local LLM calls. **Configured but unselected** — nothing currently routes here; kept for the failover decision at vikunja#399, not dead config |
| `[llm.providers.ollama]` | `base_url` | `http://127.0.0.1:11435/v1` | OQP OpenAI-compat endpoint (`/v1` suffix required) |
| `[llm.providers.mistral]` | `base_url` | `https://api.mistral.ai/v1` | Mistral OpenAI-compat endpoint |
| `[llm.providers.mistral]` | `api_key` | `env:MISTRAL_API_KEY` | Auth for Mistral calls |
| `[plugins.claude-code.summarize]` | `enabled` | `true` | Enable session transcript summarizer |
| `[plugins.claude-code.summarize]` | `provider` | `mistral` | Routes to `[llm.providers.mistral]` |
| `[plugins.claude-code.summarize]` | `model` | `mistral-medium-latest` | Live model — see [llm-providers.md](../ai-search/llm-providers.md) |
| `[prompts]` | `summarize` | `~/.memsearch/prompts/summarize-local.txt` | Custom system prompt for summarize plugin |

**Read `~/.memsearch/config.toml` directly before citing any of the above** — this table has
been wrong before (vikunja#402: it named Ollama/qwen3:14b after the config had already moved
to Mistral) and the fix for that is not re-copying values into docs, it's linking to the
single page that owns them: [llm-providers.md](../ai-search/llm-providers.md).

## Summarize plugin

The `plugins.claude-code.summarize` plugin ingests raw session transcripts from `.memsearch/spool/` and compresses them into bullet summaries, then writes the result back so later searches hit the condensed form rather than raw tool output.

**Model:** `mistral-medium-latest`, via the OpenAI-compatible `[llm.providers.mistral]` provider (`https://api.mistral.ai/v1`). This replaced an earlier Ollama-hosted `memsearch-summarize` modelfile (`qwen3:14b`, `/no_think` suffix, `temperature 0.1`, `num_predict 400`) during the 2026-08 pipeline-resilience build — if you see that modelfile referenced elsewhere as current, it is stale.

**Routing:** LLM calls for summarize go through `[llm.providers.mistral]` directly to the external Mistral API — not through OQP. **Embedding calls (`[embedding]`) are the one LLM-adjacent path that is still genuinely Ollama**, via OQP on `http://127.0.0.1:11435` (no `/v1`, native Ollama API). Do not conflate the two: summarize and embedding are separate config sections with separate providers, and only one of them changed.

**Custom prompt:** `~/.memsearch/prompts/summarize-local.txt` overrides the default system prompt. Edit this file to tune summary style without touching the memsearch library.

**No quality gate exists on this path.** `memory-compact-qc.sh` grades `compact` output, not
summarize output, and grades it for fidelity to a source that is itself summarize output —
[memory-architecture.md](memory-architecture.md)'s hop table should not be read as implying
summarize has independent quality coverage. Relatedly, `memsearch-spend.sh` meters only
`process=compact`; Mistral summarize calls are not in that meter, so any spend figure derived
from it is not total pipeline spend (see [llm-providers.md](../ai-search/llm-providers.md)).

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
# Check both watch processes are running
pm2 status memsearch-watch-fast
pm2 status memsearch-watch-templates

# Tail the current logs
tail -f ~/logs/memsearch/watch-fast-$(ls -t ~/logs/memsearch/ | grep watch-fast | head -1)
tail -f ~/logs/memsearch/watch-templates-$(ls -t ~/logs/memsearch/ | grep watch-templates | head -1)

# Manually trigger a full index run
/opt/venvs/memsearch/bin/memsearch index ~/.claude/memory/

# Run a test search from the CLI
/opt/venvs/memsearch/bin/memsearch search "grafana dashboard setup"

# Restart a watch process (e.g., after config change)
pm2 restart memsearch-watch-fast
pm2 restart memsearch-watch-templates
```

If either watch process reports index errors, check that Milvus and the Ollama queue proxy are healthy
first. memsearch will fail if embeddings can't be generated.

## Related Docs

- [memsearch-mcp.md](memsearch-mcp.md) — MCP server wrapping memsearch (agent tool surface)
- [memsearch-summarize.md](memsearch-summarize.md) — session transcript summarizer
- [memory-services.md](memory-services.md) — overview of memory layer PM2 services
- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch storage backends
- [ollama.md](../ai-search/ollama.md) — embedding inference via Ollama queue proxy
