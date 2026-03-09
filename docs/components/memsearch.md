# memsearch

memsearch is a semantic memory search tool built for Claude Code. It indexes markdown files from your agent memory directories, generates local embeddings using sentence-transformers, and auto-injects relevant memories at session start and on each prompt. When you start a Claude Code session, memsearch silently retrieves context from past sessions — decisions you made, things you learned, problems you solved — without you asking for it.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) of the architecture, tightly coupled to the Claude Code agent engine and the scoped memory system.

## Why memsearch

Claude Code sessions are stateless by default. You start a new session, Claude has no idea what happened yesterday. CLAUDE.md files help — they provide stable context about your infrastructure and conventions — but they don't capture session-to-session learnings. That's what memsearch solves.

When a Claude Code agent finishes a session, it writes a summary to its memory directory (`~/.claude/memory/agents/<agent-name>/` or `~/.claude/memory/shared/`). memsearch indexes those files and, on the next session, automatically surfaces the ones most relevant to what you're working on. The agent doesn't start from zero — it picks up context from its own history.

This is different from [qmd](qmd.md), which provides on-demand search across a broader document set (repos, compose files, infrastructure docs). memsearch is narrower and automatic — it's specifically for Claude Code memory recall, triggered by the Claude Code plugin rather than explicit search queries.

## How It Works

memsearch has two components:

**CLI tool** (`memsearch`, v0.1.7) — indexes markdown files, generates embeddings using the `all-MiniLM-L6-v2` sentence-transformer model, and stores vectors in a local Milvus Lite database (`~/.memsearch/milvus.db`). Runs entirely on CPU, no API keys needed.

**Claude Code plugin** (v0.2.2) — hooks into Claude Code sessions. On session start, it retrieves memories relevant to the project context. On each prompt, it searches for memories relevant to the current conversation. Relevant results are silently injected into the context so the agent has them available without being explicitly asked.

The database is derived — it rebuilds from the source markdown files. If you delete `milvus.db`, re-run `memsearch index` and it regenerates. The source of truth is always the markdown files in the memory directories.

## Prerequisites

- Python 3.11+
- `pip install memsearch` (or `pipx install memsearch`)
- Claude Code CLI (for the plugin integration)
- Markdown memory files to index (created by Claude Code agents during sessions)

## Configuration

memsearch configuration lives at `~/.memsearch/config.toml`:

```toml
[model]
name = "all-MiniLM-L6-v2"

[paths]
# Default memory paths (auto-detected from Claude Code)
# Add extra paths to index additional directories:
extra = [
    "~/.claude/memory/shared",
    "~/.claude/memory/agents/homelab-ops",
    "~/.claude/memory/agents/dev",
    "~/.claude/memory/agents/research"
]
```

The `[paths] extra` config is where you tell memsearch which directories to index. This should include all agent memory directories that you want searchable. The shared directory contains cross-agent knowledge; each agent directory contains domain-specific learnings.

After configuring paths, run `memsearch index` to build the initial database. Re-run it after new memory files are added — or let the memory-sync cron handle it (see [memory-sync](memory-sync.md)).

## Integration Points

**Claude Code plugin:** The primary consumer. The plugin auto-loads when Claude Code starts a session, queries memsearch for relevant context, and injects it. You don't interact with memsearch directly during a session — it works in the background.

**Scoped memory directories:** memsearch respects the agent memory structure described in the [main README](../../README.md#layer-3--multi-agent-claude-code-engine). Each agent reads from shared + its own directory, writes to its own directory. memsearch indexes all configured paths but the plugin filters results based on the active project context.

**qmd:** Complementary, not competing. qmd indexes a broader document set (infrastructure docs, compose files, repos) and serves on-demand search queries via MCP. memsearch indexes a narrower set (agent memory files) and auto-injects context. In practice, both run simultaneously — qmd for "search my docs" and memsearch for "remember what happened last session."

**memory-sync agent:** The nightly memory-sync job (see [memory-sync](memory-sync.md)) reads from the same memory directories that memsearch indexes. After memory-sync distills durable knowledge into the context repo, the next qmd reindex picks it up. The flow is: agent writes memory → memsearch makes it searchable for future sessions → memory-sync distills the durable parts → qmd indexes the distilled output.

## Gotchas and Lessons Learned

**CPU-only is fine.** Unlike qmd, which benefits significantly from GPU acceleration for embedding large document collections, memsearch indexes a relatively small set of short memory files. The `all-MiniLM-L6-v2` model is small and fast on CPU. Re-indexing a few dozen memory files takes seconds.

**The database is disposable.** `milvus.db` is a derived artifact. If it gets corrupted or you want a clean slate, delete it and re-run `memsearch index`. The markdown files are the source of truth.

**Plugin version matters.** The CLI tool and Claude Code plugin are versioned separately. Make sure the plugin version is compatible with your Claude Code version — check the memsearch repo for compatibility notes after Claude Code updates.

**Memory quality depends on agent discipline.** memsearch is only as good as the memory files agents write. If an agent writes vague session summaries ("did some work on Docker"), memsearch can't surface useful context. The CLAUDE.md project configs in this repo include guidance on writing useful memory entries — specific decisions, rationale, outcomes.

**Overlap with qmd is intentional.** Both tools index `~/.claude/memory/`, which means some content is searchable through both. This isn't a problem — they serve different access patterns. memsearch is automatic and session-scoped; qmd is on-demand and broader. The redundancy is a feature, not a bug.

## Standalone Value

memsearch requires Claude Code to be useful — it's not a general-purpose search tool. But if you're running Claude Code at all, memsearch is a significant quality-of-life improvement. The difference between a Claude Code session that starts cold and one that auto-loads relevant context from past sessions is noticeable immediately.

You can adopt memsearch without the rest of Layer 3 (PM2 agents, memory-sync, qmd). Start with a single agent writing memory files, install memsearch, and let it auto-inject context. Expand to multi-agent memory and automated sync later.

## Further Reading

- [memsearch GitHub](https://github.com/anthropics/memsearch) *(check for current repo location — may have moved)*
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)

---

## Related Docs

- [Architecture overview](../../README.md#layer-3--multi-agent-claude-code-engine) — Layer 3 context for the agent memory system
- [qmd](qmd.md) — complementary semantic search over broader document collections
- [memory-sync](memory-sync.md) — automated knowledge distillation from memory files
- [CLAUDE.md examples](../../claude-code/) — agent project configs that define memory conventions
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — memory-related cron jobs
