# memsearch

memsearch is a semantic memory search tool built for Claude Code. It indexes markdown files from your agent memory directories, generates local embeddings using sentence-transformers, and auto-injects relevant memories at session start and on each prompt. When you start a Claude Code session, memsearch silently retrieves context from past sessions — decisions you made, things you learned, problems you solved — without you asking for it.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) of the architecture, tightly coupled to the Claude Code agent engine and the scoped memory system.

## Why memsearch

Claude Code sessions are stateless by default. You start a new session, Claude has no idea what happened yesterday. CLAUDE.md files help — they provide stable context about your infrastructure and conventions — but they don't capture session-to-session learnings. That's what memsearch solves.

When a Claude Code agent finishes a session, it writes a summary to its memory directory (`~/.claude/memory/agents/<agent-name>/` or `~/.claude/memory/shared/`). memsearch indexes those files and, on the next session, automatically surfaces the ones most relevant to what you're working on. The agent doesn't start from zero — it picks up context from its own history.

This is different from [qmd](qmd.md), which provides on-demand search across a broader document set (repos, compose files, infrastructure docs). memsearch is narrower and automatic — it's specifically for Claude Code memory recall, triggered by the Claude Code plugin rather than explicit search queries.

## How It Works

memsearch has two components:

**CLI tool** (`memsearch`) — indexes markdown files, generates embeddings via a remote Ollama instance (model: `bge-m3`, 1024-dim, batch_size=16), and stores vectors in a Milvus standalone Docker container (`localhost:19530`). Requires `OLLAMA_HOST` to be set — the ollama provider reads this env var rather than `embedding.base_url` in the config.

**Claude Code plugin** (v0.2.2) — hooks into Claude Code sessions. On session start, it retrieves memories relevant to the project context. On each prompt, it searches for memories relevant to the current conversation. Relevant results are silently injected into the context so the agent has them available without being explicitly asked.

The database is derived — it rebuilds from the source markdown files. If the index needs to be rebuilt, stop the Milvus container, wipe its data volume, restart it, then re-run `memsearch index`. The source of truth is always the markdown files in the memory directories.

## Prerequisites

- Python 3.11+
- `pip install memsearch` (or `pipx install memsearch`)
- Claude Code CLI (for the plugin integration)
- Markdown memory files to index (created by Claude Code agents during sessions)

## Configuration

memsearch configuration lives at `~/.memsearch/config.toml`. The 0.2.x format uses `[embedding]`, `[reranker]`, and `[compact]` sections:

```toml
[milvus]
uri = "http://localhost:19530"
collection = "memsearch_chunks"

[embedding]
provider = "ollama"      # uses OLLAMA_HOST env var — base_url in config is ignored
model = "bge-m3"         # 1024-dim, MTEB 65, 8192-token context
batch_size = 16

[chunking]
max_chunk_size = 1500
overlap_lines = 2

[watch]
debounce_ms = 1500

[paths]
# Add extra directories to index beyond the auto-detected defaults:
extra = [
    "~/.claude/memory/"
]

[compact]
llm_provider = "anthropic"
llm_model = "claude-sonnet-4-6"

[reranker]
model = "Alibaba-NLP/gte-reranker-modernbert-base"   # empty string = disabled
```

**`OLLAMA_HOST` note:** The `ollama` provider does not read `embedding.base_url` from the config. It reads the `OLLAMA_HOST` environment variable exclusively. This must be set before any `memsearch index`, `memsearch watch`, or `memsearch compact` invocation. It is hardcoded in `~/.claude/scripts/memsearch-watch.sh` and `~/.claude/scripts/memsearch-compact.sh` for PM2 processes; for manual re-index runs, set it inline:

```bash
OLLAMA_HOST=https://ollama.<your-forge-domain> memsearch index
```

If your Ollama instance sits behind a rate-limited reverse proxy, ensure your claudebox host IP has a permanent bypass rule configured — a full re-index issues many embedding requests in rapid succession and will trigger rate limiting without it.

**Model history:** The embedding stack went through two upgrades: `local/all-MiniLM-L6-v2` (384-dim, CPU-only, original) → `ollama/nomic-embed-text` (768-dim, forge GPU, Phase 3 initial) → `ollama/bge-m3` (1024-dim, forge GPU, Phase 3 final, current). Each transition required `memsearch reset && memsearch index` due to dimension incompatibility. The 22 files that failed to index under nomic-embed-text (512-token context limit) indexed successfully under bge-m3 (8192-token context).

The `[paths] extra` config is where you tell memsearch which directories to index beyond what Claude Code auto-detects. The shared directory contains cross-agent knowledge; each agent directory contains domain-specific learnings.

After configuring paths, run `memsearch index` to build the initial database. Re-run it after new memory files are added — or let the memory-sync cron handle it (see [memory-sync](memory-sync.md)).

A companion PM2 process (`memsearch-watch`, always-on) watches all session and working memory directories for changes and re-indexes on write with a 5-second debounce — so memories written during a session are searchable within seconds, not just after the nightly sync. See [Real-Time Indexing](#real-time-indexing) below.

A companion PM2 job (`memsearch-compact`, runs as part of the nightly memory pipeline) uses an LLM to summarize and compress noisy session memory files. It processes two locations: all per-project session stores (`~/.claude/projects/*/.memsearch/memory/`) and the global session store (`~/.memsearch/memory/`). For each, it compacts today's and yesterday's `.md` files — calls the configured LLM to produce a condensed summary and writes it back to the same file. `memsearch-watch` picks up the rewritten file and re-indexes it, so searches reflect the summarized version rather than the raw transcript. This is LLM-powered content compaction — not database-level compaction. `OLLAMA_HOST` must be set for this script too (see note above). See [`pm2/ecosystem.config.js.example`](../../pm2/ecosystem.config.js.example) for the job definition.

## Reranker (new in 0.2.x)

memsearch 0.2.x adds a cross-encoder reranker that re-scores search results after the initial vector retrieval. This significantly improves result quality for session-tier memory, which tends to be noisy (many short, similar entries).

Enable it by setting the model in your config:

```bash
memsearch config set reranker.model "Alibaba-NLP/gte-reranker-modernbert-base"
```

The model (~500MB) downloads from HuggingFace on the first search call after configuration — not at config-set time. Two backends are auto-detected: ONNX Runtime (preferred, CPU-only) or sentence-transformers (PyTorch). If `onnxruntime` is not installed, the PyTorch backend is used automatically. Leave `reranker.model` empty to disable.

## Real-Time Indexing

The `memsearch-watch` PM2 process keeps the index current without waiting for a nightly batch run. It watches all session and working memory directories with a 5-second debounce — any write to a watched path triggers incremental re-indexing within seconds.

**Watched directories** (discovered dynamically at startup):
- All per-project session dirs: `~/.claude/projects/*/.memsearch/memory/` (one per Claude Code project)
- Global session dir: `~/.memsearch/memory/`
- Working memory: `~/.claude/memory/` (shared + per-agent subdirs)

The script (`~/.claude/scripts/memsearch-watch.sh`) uses `find` at startup to collect all matching `.memsearch/memory/` directories, then passes the full list to `memsearch watch --debounce-ms 5000`. New project directories added after startup aren't picked up until the process restarts — a PM2 restart is sufficient.

**Practical effect:** when an agent writes a memory file mid-session (via memory-flush or a Stop hook), it becomes searchable immediately. The archival-search skill benefits from this — its memsearch queries reflect the current session's writes, not just yesterday's batch.

## Integration Points

**Claude Code plugin:** The primary consumer. The plugin auto-loads when Claude Code starts a session, queries memsearch for relevant context, and injects it. You don't interact with memsearch directly during a session — it works in the background.

**Scoped memory directories:** memsearch respects the agent memory structure described in the [main README](../../README.md#layer-3--multi-agent-claude-code-engine). Each agent reads from shared + its own directory, writes to its own directory. memsearch indexes all configured paths but the plugin filters results based on the active project context.

**qmd:** Complementary, not competing. qmd indexes a broader document set (infrastructure docs, compose files, repos) and serves on-demand search queries via MCP. memsearch indexes a narrower set (agent memory files) and auto-injects context. In practice, both run simultaneously — qmd for "search my docs" and memsearch for "remember what happened last session."

**archival-search skill:** The recommended interface for manual memory retrieval. It queries memsearch (session + working tiers) and qmd (working + distilled tiers) in a single call, merges the results, and labels each result by tier. Use `archival-search` rather than running `memsearch search` directly when you want a complete picture across all memory tiers.

**memory-sync agent:** memsearch captures the **session tier** — raw session summaries auto-written by the Stop hook. The nightly memory-sync job (see [memory-sync](memory-sync.md)) scans these session notes and promotes durable items to the **working tier** (`~/.claude/memory/`). Working notes that pass the "would this matter in 3 months?" test are further promoted to the **distilled tier** (context repo). The flow across tiers: session (memsearch auto-capture) → working (memory-sync promotion) → distilled (memory-sync distillation) → qmd indexes distilled output for long-term search.

## Gotchas and Lessons Learned

**Embedding is remote — Ollama availability matters.** memsearch now uses a remote Ollama instance for embeddings (bge-m3 via GPU). If the Ollama host is unreachable, `memsearch-watch` will fail silently on each file change — writes to memory directories still succeed, but the index won't update until Ollama is back. Check `pm2 logs memsearch-watch` if searches feel stale. A local fallback is not configured; if you need offline embedding, switch `provider` back to `onnx` and run `memsearch reset && memsearch index`.

**The index is disposable.** The Milvus vector database is a derived artifact — all data in it was generated from the source markdown files. If the index gets corrupted or dimensions change (e.g. after a model switch), stop the Milvus container, clear its data volume, restart it, and re-run `memsearch index`. The markdown files are the source of truth. Stop `memsearch-watch` first to avoid write conflicts during re-indexing.

**OLLAMA_HOST is hardcoded in both watch and compact scripts.** When using the `ollama` embedding provider, `OLLAMA_HOST` is set directly in `~/.claude/scripts/memsearch-watch.sh` and `~/.claude/scripts/memsearch-compact.sh`. Any domain change, cert rotation, or subdomain reconfiguration on the forge SWAG proxy requires updating both scripts and restarting the `memsearch-watch` PM2 process. There is no environment-level config for this — it's not in `config.toml`.

**Switching embedding providers requires a full re-index.** Vector dimensions differ between models (384 dims for all-MiniLM-L6-v2, 1024 dims for bge-m3 — the current provider). After changing `embedding.provider` or `model`, stop `memsearch-watch`, clear the Milvus data volume and restart the container (schema is dimension-locked), then re-run `memsearch index`. Restart `memsearch-watch` when done.

**Plugin version matters.** The CLI tool and Claude Code plugin are versioned separately. Make sure the plugin version is compatible with your Claude Code version — check the memsearch repo for compatibility notes after Claude Code updates.

**Plugin availability isn't guaranteed.** The Claude Code plugin ecosystem may change between versions. Before setting up the plugin, verify it exists: check `claude --help` for plugin commands, then look for memsearch in the marketplace. If the plugin isn't available, memsearch still works as a standalone CLI tool — you lose the auto-inject hooks but can use `memsearch search "query"` manually or via shell commands from within Claude Code sessions. The core indexing and search functionality doesn't depend on the plugin.

**Memory quality depends on agent discipline.** memsearch is only as good as the memory files agents write. If an agent writes vague session summaries ("did some work on Docker"), memsearch can't surface useful context. The CLAUDE.md project configs in this repo include guidance on writing useful memory entries — specific decisions, rationale, outcomes.

**Overlap with qmd is intentional.** Both tools index `~/.claude/memory/`, which means some content is searchable through both. This isn't a problem — they serve different access patterns. memsearch is automatic and session-scoped; qmd is on-demand and broader. The redundancy is a feature, not a bug.

## Standalone Value

memsearch requires Claude Code to be useful — it's not a general-purpose search tool. But if you're running Claude Code at all, memsearch is a significant quality-of-life improvement. The difference between a Claude Code session that starts cold and one that auto-loads relevant context from past sessions is noticeable immediately.

You can adopt memsearch without the rest of Layer 3 (PM2 agents, memory-sync, qmd). Start with a single agent writing memory files, install memsearch, and let it auto-inject context. Expand to multi-agent memory and automated sync later.

## Further Reading

- [memsearch GitHub](https://github.com/zilliztech/memsearch) — Zilliz project, actively maintained
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)

---

## Related Docs

- [Architecture overview](../../README.md#layer-3--multi-agent-claude-code-engine) — Layer 3 context for the agent memory system
- [qmd](qmd.md) — complementary semantic search over broader document collections
- [memory-sync](memory-sync.md) — automated knowledge distillation from memory files
- [CLAUDE.md examples](../../claude-code/) — agent project configs that define memory conventions
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — memory-related cron jobs
