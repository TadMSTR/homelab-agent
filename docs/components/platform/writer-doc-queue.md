# writer-doc-queue

`writer-doc-queue` is a daily PM2 cron that launches a headless writer agent session to
process pending entries in the forge doc queue — the consumer side of
[doc-health](doc-health.md)'s findings and of build agents' post-build doc requests.

- **Script:** `~/scripts/writer-doc-queue-run.sh`
- **Schedule:** `0 21 * * *` (daily, 21:00)
- **No listening port** — runs as a scheduled batch job, not always-on

## How it works

1. Cron fires `writer-doc-queue-run.sh`, which does a **pre-flight check** before spending
   any API tokens: it scans `~/.claude/task-queue/*.yml` directly (task-queue-mcp has no
   REST API) for tasks with `target_agent: writer` and `status` in `approved`/`submitted`.
2. If the pending count is `0`, the script logs and exits — no Claude session is launched.
3. Otherwise it sources writer agent secrets from `/opt/appdata/agents/writer/.env`
   (`SCOPED_MCP_BEARER_TOKEN` etc. — mirrors the task-dispatcher's `load_agent_env()`,
   SMCP-28). Without this, the writer project's `.mcp.json` bearer header resolves empty and
   the session silently starts with no scoped-mcp tools.
4. Launches `claude -p --dangerously-skip-permissions` from `~/.claude/projects/writer`
   with the prompt: *"You have pending documentation tasks in the queue. Run the
   writer-doc-queue skill to process them."*
5. The invoked session runs the `writer-doc-queue` skill, which reads
   `~/.claude/memory/shared/doc-update-queue.jsonl`, processes `pending` entries in priority
   order (routing by `type` per the writer project's CLAUDE.md), writes/updates docs,
   commits, and marks each entry `done` (or `pending-review` if blocked).

Manual writer sessions (interactive or task-triggered) also process the queue safely — the
`in-progress`/`done` status field on each queue entry prevents double-processing between the
cron and an ad-hoc session.

## Configuration

| Setting | Value |
|---------|-------|
| Task queue scan dir | `~/.claude/task-queue/` (flat YAML files) |
| Doc queue | `~/.claude/memory/shared/doc-update-queue.jsonl` |
| Writer secrets | `/opt/appdata/agents/writer/.env` |
| Log | `~/logs/writer-doc-queue.log` |

## Dependencies

- **task-queue-mcp** — YAML task files gate whether a session launches at all
- **doc-health** — primary producer of doc queue entries (coverage gaps, staleness)
- **scoped-mcp** (writer manifest) — githost-mcp, system-ops, qmd, matrix-mcp, etc. used
  during doc writing
- **doc-update-queue.jsonl routing table** (writer project CLAUDE.md) — determines
  destination repo/path per queue entry `type`

## Operations

```bash
# Check service status (waiting restart between daily runs is normal)
pm2 show writer-doc-queue

# View logs
tail -50 ~/logs/writer-doc-queue.log

# Force a run
pm2 restart writer-doc-queue

# Check pending queue entries manually
grep -c '"status": "pending"' ~/.claude/memory/shared/doc-update-queue.jsonl
```

## Related docs

- [doc-health](doc-health.md) — writes most of the entries this cron consumes
