# writer-doc-queue

`writer-doc-queue` is a daily PM2 cron that launches a headless writer agent session to
process approved documentation tasks on the task queue — the consumer side of
[doc-health](doc-health.md)'s findings and of build agents' post-build doc requests.

- **Script:** `~/scripts/writer-doc-queue-run.sh`
- **Schedule:** `0 21 * * *` (daily, 21:00)
- **No listening port** — runs as a scheduled batch job, not always-on

> The doc-side work-list used to be a separate flat file
> (`~/.claude/memory/shared/doc-update-queue.jsonl`), read independently of the task queue
> that triggered this cron. That split queue was retired 2026-08-16 — the task queue is now
> the writer's only work-list, and this cron's pre-flight check and the writer's skill both
> read it. See [doc-health](doc-health.md) for how findings reach the queue.

## How it works

1. Cron fires `writer-doc-queue-run.sh`, which does a **pre-flight check** before spending
   any API tokens: it scans `~/.claude/task-queue/*.yml` directly (task-queue-mcp has no
   REST API) for tasks with `target_agent: writer` and `status: approved`.
2. If the pending count is `0`, the script logs and exits — no Claude session is launched.
3. Otherwise it sources writer agent secrets from `/opt/appdata/agents/writer/.env`
   (`SCOPED_MCP_BEARER_TOKEN` etc. — mirrors the task-dispatcher's `load_agent_env()`,
   SMCP-28). Without this, the writer project's `.mcp.json` bearer header resolves empty and
   the session silently starts with no scoped-mcp tools.
4. Launches `claude -p --dangerously-skip-permissions` from `~/.claude/projects/writer`,
   naming the specific approved task IDs it found in the launch prompt: *"You have approved
   documentation tasks in the queue: `<id>, <id>, ...`. Run the writer-task-queue skill to
   process them."*
5. The invoked session runs the `writer-task-queue` skill (renamed from `writer-doc-queue`
   2026-08-16), which claims each named task via `task-queue-mcp: update_task(status:
   in-progress)`, writes/updates the doc, commits, and closes it (`status: completed`) — or
   `park_task`s it with the blocking question if it can't proceed.

Manual writer sessions (interactive or task-triggered) also process the queue safely — a
task's `in-progress`/`completed` status prevents double-processing between the cron and an
ad-hoc session, the same guarantee the retired JSONL's status field used to provide.

## Configuration

| Setting | Value |
|---------|-------|
| Task queue scan dir | `~/.claude/task-queue/` (flat YAML files) |
| Writer secrets | `/opt/appdata/agents/writer/.env` |
| Log | `~/logs/writer-doc-queue.log` |

## Dependencies

- **task-queue-mcp** — the writer's sole work-list; gates whether this cron launches a
  session at all, and is what the launched session reads and writes to
- **doc-health** — primary producer of doc tasks (coverage gaps, staleness) — submits
  `task_type: docs` tasks directly rather than appending to a queue file
- **scoped-mcp** (writer manifest) — githost-mcp, system-ops, qmd, matrix-mcp, etc. used
  during doc writing

## Operations

```bash
# Check service status (waiting restart between daily runs is normal)
pm2 show writer-doc-queue

# View logs
tail -50 ~/logs/writer-doc-queue.log

# Force a run
pm2 restart writer-doc-queue

# Check approved writer tasks manually
grep -l 'target_agent: writer' ~/.claude/task-queue/*.yml | xargs grep -l 'status: approved'
```

## Related docs

- [doc-health](doc-health.md) — writes most of the tasks this cron consumes
