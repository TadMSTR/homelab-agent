# Memory Sync

Memory sync is the automated knowledge distillation pipeline. A headless Claude Code agent runs as a PM2 cron job at 4:00 AM daily, reads recent memory from Claude Code sessions and (optionally) LibreChat conversations, identifies durable knowledge worth keeping, and commits distilled notes to the persistent context repository. Knowledge accumulates without manual curation.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) of the architecture. It's the piece that closes the loop — without it, agent memory files pile up as raw session notes that nobody reviews. With it, the valuable parts flow into the context repo where they become available to all future sessions.

## Why Memory Sync

AI assistants are stateless. Every workaround to this — CLAUDE.md files, memory directories, semantic search — is a hack to make the next session start with context from the last one. The problem is that these memory files accumulate noise. Session summaries include ephemeral details ("restarted the container three times before it worked") alongside durable decisions ("switched from Redis to Valkey because of the license change").

Memory sync acts as an editorial filter. It reads the raw memory, applies the "would this matter in 3 months?" test, and distills only the genuinely durable knowledge into clean, dated markdown files in the context repo. The context repo is what qmd indexes, what CLAUDE.md files reference, and what future sessions actually draw from.

Without memory sync, you'd need to manually review agent memory files and copy the good parts into your context repo. That's exactly the kind of busywork that should be automated.

## Memory Tiers

Memory-sync manages a 3-tier memory pipeline plus an always-visible core context layer. Each tier has different retention, purpose, and storage:

| Tier | Location | Retention | Purpose |
|------|----------|-----------|---------|
| Session | `.memsearch/memory/YYYY-MM-DD.md` (per-project) | 30 days | Raw session notes, auto-captured by memsearch Stop hook |
| Working | `~/.claude/memory/shared/` and `~/.claude/memory/agents/*/` | 90 days (unless refreshed) | Promoted from session or written by agents during work |
| Distilled | Context repo `memory/distilled/` | Permanent (git-backed) | Passes the "would this matter in 3 months?" test |
| Core Context | `~/.claude/memory/core-context.md` | Permanent (managed) | Always-visible profile/projects/constraints/decisions; injected at every session start via SessionStart hook; 40-line cap; updated via `core-memory-update` skill |

Working and distilled notes use YAML frontmatter for metadata:

```yaml
# Working note
---
tier: working
created: 2026-03-13
source: memory-sync
expires: 2026-06-13
tags: [docker, decision]
---

# Distilled note
---
tier: distilled
date: 2026-03-13
source: claude-code
promoted_from: some-working-note.md
tags: [docker, decision]
---
```

## How It Works

The memory-sync agent is defined in [`claude-code/projects/memory-sync.md`](../../claude-code/projects/memory-sync.md) and runs as a PM2 cron job (`memory-pipeline`). The workflow is an 8-step consolidation pipeline:

1. **Session scan.** Read memsearch session files from the last 7 days across all project stores. Identify entries containing infrastructure decisions, tool configurations, bug fixes, architectural decisions, or lessons learned. Skip empty session headers.

2. **Promote to working.** For each durable session entry, check if a working note already covers the topic. If not, write a new working note with frontmatter. If partially covered, update the existing note and refresh its expiry date.

3. **Chat import.** Read the latest chat interface memory export (e.g., LibreChat MongoDB dump). Apply the same criteria as step 1 — promote durable entries to working notes.

4. **Working review.** Read all working notes. For notes older than 14 days, evaluate: ready for distillation? Still relevant but not ready? Superseded or inaccurate? Delete notes that are no longer valid.

5. **Promote to distilled.** Distill qualifying working notes into permanent records in the context repo. Check existing distilled notes first to avoid duplicates. Git pull, commit, and push.

6. **Expire stale.** Delete working notes past their 90-day expiry date that weren't promoted to distilled. Log each deletion.

7. **Dedup check.** Scan working memory for topical duplicates — notes covering the same decision, fact, or event. Merge into the more complete note and delete the other.

8. **Log metrics and health report.** Output counts (sessions scanned, notes promoted/updated/distilled/expired/deduped, errors) plus health stats (note counts by tier, upcoming expirations, notes with missing frontmatter).

## Configuration

The agent itself is configured via its CLAUDE.md project file (see [`claude-code/projects/memory-sync.md`](../../claude-code/projects/memory-sync.md) for the template). The PM2 cron definition is in [`pm2/ecosystem.config.js.example`](../../pm2/ecosystem.config.js.example).

Key paths to configure:

| Path | Purpose | Tier |
|------|---------|------|
| `.memsearch/memory/` (per-project) | Session notes (auto-captured) | Session |
| `~/.claude/memory/shared/` | Cross-agent working memory | Working |
| `~/.claude/memory/agents/*/` | Per-agent working memory | Working |
| `~/.claude/memory/chat-staging/` | Chat interface exports (optional input) | — |
| `~/repos/YOUR_CONTEXT_REPO/memory/distilled/` | Permanent distilled output | Distilled |
| `~/.claude/memory/shared/memory-schema.md` | Tier schema, frontmatter format, tag taxonomy | — |

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

**PM2 cron (`memory-pipeline`):** Runs at 4:00 AM daily, before the qmd reindex at 5:00 AM. This sequencing is deliberate — distilled notes land in the context repo, then qmd indexes them in the next cycle.

**qmd:** Indexes the distilled output directory as part of the context repo collection. Once qmd reindexes, the distilled knowledge is searchable by all agents.

**memsearch:** Indexes session-tier memory files. The pipeline is: memsearch auto-captures session summaries → makes them available for immediate recall → memory-sync scans sessions and promotes durable items to working tier → reviews working notes and promotes mature ones to distilled tier → qmd indexes distilled output for long-term search.

**git:** The memory-sync agent commits and pushes distilled notes using plain git shell commands — not GitHub MCP. If you're running this on a machine with GitHub SSH keys configured, it works without additional setup. GitHub MCP is for remote operations (PRs, issues, reading unchecked-out repos) and isn't involved here.

## Gotchas and Lessons Learned

**The agent needs API access.** Memory-sync runs a headless Claude Code session, which means it uses your Claude API quota. At one run per day with typically small inputs, the cost is negligible — but it's not free. If you're on a usage-limited plan, factor this in.

**Empty runs are normal.** If nothing meaningful happened in the last 7 days, the agent exits without committing anything. Don't be alarmed by "no changes" in the PM2 logs — that's the system working as designed.

**Chat memory export is the fragile part.** The Claude Code memory side is straightforward — it's just markdown files on disk. The chat interface export depends on your specific chat UI. For LibreChat, this means querying MongoDB for memory entries. If you change chat UIs, the export adapter needs updating. The project config describes the staging file format so the distillation side stays stable regardless of the source.

**Scope your LibreChat export to your own user if you share the instance.** LibreChat stores memory entries per user in MongoDB, but a naive `find({})` query returns every user's entries. If other people have LibreChat accounts on the same instance, their memory ends up in the staging file and gets distilled into your context repo. Filter the query by your user ObjectId:

```js
db.memoryentries.find({ user: ObjectId("YOUR_USER_OBJECTID") })
```

Find your ObjectId with:

```bash
docker exec librechat-mongodb mongosh --quiet --eval \
  'db = db.getSiblingDB("LibreChat"); printjson(db.users.find({}, {_id:1, username:1}).toArray());'
```

Other users' memories stay in MongoDB and are covered by your Docker backup strategy — they just don't flow into your context repo.

**Headless Claude Code has quirks.** Running Claude Code non-interactively took some trial and error. The key findings:

- Passing the prompt as a positional argument (`claude -p "prompt"`) hangs without a TTY. Pipe the prompt via stdin instead: `echo "prompt" | claude -p`.
- The `--project` flag doesn't exist in current Claude Code versions. Instead, `cd` into the project directory before invoking `claude` — it picks up CLAUDE.md from cwd via project resolution.
- Headless mode requires `--dangerously-skip-permissions` because there's no TTY to approve tool use. This is expected for automated agent runs but means you should review the agent's CLAUDE.md carefully to ensure it can't do anything destructive.
- Add a timeout wrapper (`timeout 600 claude -p ...`) to prevent runaway sessions. Ten minutes is generous for the 8-step consolidation pipeline.
- Use `--add-dir` to grant the headless session access to directories outside cwd (memory dirs, context repo) that the agent needs to read and write.

These details matter if you're building any PM2-scheduled Claude Code job, not just memory-sync.

**Review the output occasionally.** The agent does a good job of filtering, but it's worth skimming the distilled notes weekly to catch anything that slipped through as noise or to spot knowledge gaps where something durable was missed. This gets better over time as the agent's CLAUDE.md instructions get refined.

**Concurrency and lock file.** The wrapper script uses a lock file (`~/.claude/memory-sync.lock`) to prevent overlapping runs. Stale locks older than 10 minutes are automatically removed. If the agent crashes, the lock is cleaned up via a bash `trap`.

**Timeout.** The wrapper script uses `timeout 600` (10 minutes) to prevent runaway sessions. The expanded 8-step pipeline needs more time than the original single-step distillation.

**Idempotent by design.** Runs are safe to repeat. The agent checks for existing working notes before creating new ones, checks existing distilled notes before promoting, and only expires notes with a valid `expires` date strictly in the past. Notes without valid frontmatter are flagged in the health report rather than deleted.

**Git conflicts are unlikely but possible.** If you're manually committing to the context repo's distilled directory at the same time the agent runs, you could get a merge conflict. The agent uses `git pull --rebase` before committing and aborts cleanly if the rebase fails. The agent runs at 4 AM specifically to avoid this, but if you're a night owl, be aware.

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
