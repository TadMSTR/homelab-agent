# Memory Sync

Memory sync is the automated knowledge distillation pipeline. A headless Claude Code agent runs as a PM2 cron job at 4:00 AM daily, reads recent memory from Claude Code sessions and (optionally) LibreChat conversations, identifies durable knowledge worth keeping, and commits distilled notes to the persistent context repository. Knowledge accumulates without manual curation.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) of the architecture. It's the piece that closes the loop — without it, agent memory files pile up as raw session notes that nobody reviews. With it, the valuable parts flow into the context repo where they become available to all future sessions.

## Why Memory Sync

AI assistants are stateless. Every workaround to this — CLAUDE.md files, memory directories, semantic search — is a hack to make the next session start with context from the last one. The problem is that these memory files accumulate noise. Session summaries include ephemeral details ("restarted the container three times before it worked") alongside durable decisions ("switched from Redis to Valkey because of the license change").

Memory sync acts as an editorial filter. It reads the raw memory, applies the "would this matter in 3 months?" test, and distills only the genuinely durable knowledge into clean, dated markdown files in the context repo. The context repo is what qmd indexes, what CLAUDE.md files reference, and what future sessions actually draw from.

Without memory sync, you'd need to manually review agent memory files and copy the good parts into your context repo. That's exactly the kind of busywork that should be automated.

## How It Works

The memory-sync agent is defined in [`claude-code/projects/memory-sync.md`](../../claude-code/projects/memory-sync.md) and runs as a PM2 cron job. The workflow:

1. **(Optional) Export chat interface memory.** If you use LibreChat or another chat UI with memory features, an export script dumps recent memory entries to a staging file. This is adapter-specific — the project config describes the staging format but the export mechanism depends on your chat UI.

2. **Read Claude Code memory files.** The agent scans `~/.claude/memory/shared/` and each agent's directory (`~/.claude/memory/agents/*/`), looking for entries from the last 7 days.

3. **Read any chat memory exports.** If a staging file exists from step 1, the agent reads it.

4. **Identify durable knowledge.** The agent filters for entries that contain infrastructure decisions, new tool configurations, bug fixes worth remembering, architectural decisions with rationale, or lessons learned. Ephemeral details (debug sessions, temporary workarounds, routine maintenance) get skipped.

5. **Check for duplicates.** Before writing anything, the agent reads existing distilled notes to avoid re-capturing knowledge that's already in the context repo.

6. **Write distilled notes.** New knowledge gets written as dated markdown files (`YYYY-MM-DD-<topic-slug>.md`) with structured metadata: date, source (claude-code or chat), summary, details, and rationale.

7. **Commit and push.** The agent commits the new files to the context repo and pushes to GitHub. The next qmd reindex (5:00 AM) picks up the new content and makes it searchable.

## Configuration

The agent itself is configured via its CLAUDE.md project file (see [`claude-code/projects/memory-sync.md`](../../claude-code/projects/memory-sync.md) for the template). The PM2 cron definition is in [`pm2/ecosystem.config.js.example`](../../pm2/ecosystem.config.js.example).

Key paths to configure:

| Path | Purpose |
|------|---------|
| `~/.claude/memory/shared/` | Cross-agent shared memory (input) |
| `~/.claude/memory/agents/*/` | Per-agent memory directories (input) |
| `~/.claude/memory/chat-staging/` | Chat interface memory exports (optional input) |
| `~/repos/YOUR_CONTEXT_REPO/memory/distilled/` | Distilled output (committed to git) |

## Prerequisites

- Claude Code CLI with a valid subscription
- A context repository (git repo where distilled knowledge lives)
- PM2 for cron scheduling
- Agent memory directories with content (created by regular Claude Code usage)
- Optional: LibreChat or other chat UI with exportable memory

## The Distillation Rules

The memory-sync agent follows specific rules to keep the output useful:

**Only durable knowledge.** The "would this matter in 3 months?" test is the primary filter. A session where you spent an hour debugging a Docker networking issue isn't worth capturing unless you discovered something non-obvious. The decision to switch from bridge to host networking, and why — that's durable.

**Never modify existing files.** Distilled notes are append-only. The agent adds new files but never edits or deletes existing ones. This prevents an automated process from accidentally overwriting manually curated context.

**Maximum 10 notes per run.** A safety cap to prevent flooding the repo after a week of heavy agent usage. If there's more durable knowledge than 10 entries, it'll catch the remainder on the next run.

**Concise, not comprehensive.** Each distilled note captures a decision or fact and its rationale, not a full narrative of the session. Think "we switched to Valkey for Redis-compatible caching because of the SSPL license change" not a blow-by-blow of the migration.

## Integration Points

**PM2 cron:** Runs at 4:00 AM daily, before the qmd reindex at 5:00 AM. This sequencing is deliberate — distilled notes land in the context repo, then qmd indexes them in the next cycle.

**qmd:** Indexes the distilled output directory as part of the context repo collection. Once qmd reindexes, the distilled knowledge is searchable by all agents.

**memsearch:** Indexes the raw memory files that memory-sync reads from. The pipeline is: agents write raw memory → memsearch makes it available for immediate recall → memory-sync distills the durable parts → qmd makes the distilled output searchable long-term.

**GitHub MCP:** The memory-sync agent uses git to commit and push distilled notes. If you're running this on a machine with GitHub SSH keys configured, it works without additional setup.

## Gotchas and Lessons Learned

**The agent needs API access.** Memory-sync runs a headless Claude Code session, which means it uses your Claude API quota. At one run per day with typically small inputs, the cost is negligible — but it's not free. If you're on a usage-limited plan, factor this in.

**Empty runs are normal.** If nothing meaningful happened in the last 7 days, the agent exits without committing anything. Don't be alarmed by "no changes" in the PM2 logs — that's the system working as designed.

**Chat memory export is the fragile part.** The Claude Code memory side is straightforward — it's just markdown files on disk. The chat interface export depends on your specific chat UI. For LibreChat, this means querying MongoDB for memory entries. If you change chat UIs, the export adapter needs updating. The project config describes the staging file format so the distillation side stays stable regardless of the source.

**Review the output occasionally.** The agent does a good job of filtering, but it's worth skimming the distilled notes weekly to catch anything that slipped through as noise or to spot knowledge gaps where something durable was missed. This gets better over time as the agent's CLAUDE.md instructions get refined.

**Git conflicts are unlikely but possible.** If you're manually committing to the context repo's distilled directory at the same time the agent runs, you could get a merge conflict. The agent runs at 4 AM specifically to avoid this, but if you're a night owl, be aware.

## Standalone Value

Memory sync only makes sense if you're already running Claude Code with the memory directory structure (Layer 3). It's not useful on its own. But within that context, it's the difference between a memory system that works and one that actually improves over time. Without memory sync, agent memory is write-only — knowledge goes in but never gets curated or promoted to the persistent context. With it, the system self-maintains.

You can start without memory sync and add it later once you have a few weeks of agent memory accumulated. That's actually a good approach — it gives you material to validate the distillation quality against.

## Further Reading

- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
- [PM2 process manager](https://pm2.keymetrics.io/)

---

## Related Docs

- [Architecture overview](../../README.md#the-memory--context-system) — the four-layer memory system
- [qmd](qmd.md) — indexes the distilled output for semantic search
- [memsearch](memsearch.md) — indexes the raw memory files for session recall
- [CLAUDE.md examples](../../claude-code/) — agent project configs including memory-sync
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — memory-sync cron definition
