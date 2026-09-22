# Harlock (personal-agent) — decommissioned 2026-08-08

Harlock was a resident Matrix bot agent that maintained a persistent Claude Code session and
responded in a dedicated Matrix room, handling open-ended personal assistant work. Unlike
task-queue agents that start and stop per-task, it ran as an always-on PM2 process,
`personal-agent-harlock`.

## Decommission

Retired 2026-08-08, Phase 0 of the `githost-mcp` workspace-policy build (vikunja#367 records
the residue this left behind). `/etc/forge/workspace-policy.yml` documents the decision inline:
Harlock is decommissioned rather than scoped under the policy's per-agent model.

Confirmed absent from every live surface as of 2026-09-21: no `personal-agent-harlock` PM2
process (`pm2 jlist`), no crontab entry, no host process, no Docker container. The
`agent-harlock` system user (uid 981) and the `~/repos/personal/personal-agent` repo are both
still present on disk but idle — last session activity (rollover notes, session notes,
archived transcripts) was 2026-07-09, a full month before the recorded decommission date, so
the bot appears to have gone quiet before the formal retirement caught up to it.

**Known incomplete cleanup (vikunja#367, still open):** `githost-mcp`'s `ecosystem.config.js`
still declares a `harlock` entry, `~/.secrets/githost-mcp-harlock.env` still holds a live
`AUDIT_SIGNING_KEY` for a process that no longer exists, and
`~/.claude/manifests/harlock-agent.yml` still exists with no decommission marker in the file
itself. None of this is reachable — no process loads it — but it hasn't been swept up yet.

**A leftover you will still find running:** `harlock-archive.service` / `.timer` (systemd,
not PM2 — `systemctl list-units | grep harlock`) still fire daily, cold-archiving whatever is
left under `/home/agent-harlock/.claude`. This is expected: it's a oneshot cleanup unit, not
evidence Harlock itself is alive. vikunja#917 flags the broader gap this exposed — forge's
service inventory reads only `pm2 jlist`, so a systemd-managed leftover like this one is
invisible to every existing health check.

There is no resident personal-assistant bot on forge today. If Harlock or something like it
is revived, treat this page's architecture section below as a starting reference, not a
description of anything currently running — it also predates the 2026-09-17 memsearch
retirement (see [memsearch.md](../memory/memsearch.md#retirement)); Harlock's memory access
was wired to `memsearch-mcp`, which no longer exists.

## What it was

- **PM2 name:** `personal-agent-harlock`, script `~/repos/personal/personal-agent/start.sh`,
  always-on, isolated user `agent-harlock`
- **Matrix auto-relay:** the Claude subprocess had no Matrix send tool. `manager.py` (running
  as the operator user) owned the sole Matrix connection, ran the subprocess per turn, and
  posted its final text back to `#harlock` as the bot user, threaded and chunked. The
  subprocess itself ran isolated as `agent-harlock` with an AppArmor profile and no way to
  address Matrix directly.
- **Identity anchor:** `SOUL.md` at the project root was prepended to the first prompt of every
  new session, giving Harlock persistent identity context across rollovers.
- **Memory:** three read paths — `memsearch-mcp` (hybrid vector+BM25+reranker), 
  `memory-metadata-mcp` (structured filtering), `qmd` (doc search) — plus session/working note
  tiers under `~/.claude/memory/agents/harlock/`, indexed into memsearch by an idle-harvest
  process.
- **Session rollover:** at a configured input-token budget, the manager summarized the
  conversation tail via Ollama and started a fresh session with the summary injected.
- **Rollover QC:** a weekly cron (`harlock-rollover-qc`, Sundays) scored the week's rollover
  notes for quality and posted PASS/FAIL to `#harlock` via `matrix-mcp`.
- **scoped-mcp surface:** a dedicated manifest — `searxng-mcp`, `memsearch-mcp`,
  `memory-metadata-mcp`, `qmd`, and read-only `githost-mcp` (no `matrix-mcp` module; all
  Matrix output went through the manager's auto-relay, not an agent tool call).

## Related Docs

- [memsearch.md](../memory/memsearch.md) — the search backend Harlock's memory access depended
  on, itself retired 2026-09-17
- [scoped-mcp.md](scoped-mcp.md) — manifest structure and the workspace-policy model that
  formally excludes Harlock
