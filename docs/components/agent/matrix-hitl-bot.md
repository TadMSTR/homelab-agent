# matrix-hitl-bot — decommissioned 2026-09-27

matrix-hitl-bot was the Matrix front end for scoped-mcp's in-session HITL approval flow (SMCP-14
Phase C). When an agent called a HITL-gated tool, scoped-mcp rejected the call and posted an
"approval required" prompt into the agent's own notify room; the bot let the operator approve or
deny by replying in that room, authenticating the sender and calling `/hitl/approve` or
`/hitl/deny` with the fronted agent's bearer token.

## Decommission

Retired 2026-09-27, `operator-panel-2026-09` p1 (`TadMSTR/scoped-mcp` PR #91, v1.17.0 — signed
Ed25519 HITL approvals under `enforce`). The build's own record states it plainly: "its only
caller, `matrix-hitl-bot`, is stopped and removed from PM2 in the same phase — the token goes
with it." `POST /hitl/approve` is unregistered under `enforce` regardless of whether a caller
exists for it, so the bot's core mechanism could not have worked even had it kept running.

Confirmed absent from every live surface as of 2026-09-28: no `matrix-hitl-bot` PM2 process
(`pm2 jlist`), no Docker container. Approval is now **terminal-only**: Ted runs
`sudo -u forge-approver /opt/venvs/scoped-mcp/bin/scoped-mcp-approve <approval_id>` at a
terminal, password-prompted, against the dedicated `forge-approver` account that alone holds the
Ed25519 private key. See [scoped-mcp.md](scoped-mcp.md#hitl-gates-sysadmin-only) for the current
flow and the phase doc for the full build record
(`host-forge-knowledge-base/phases/operator-panel-2026-09-p1-signed-approvals.md`).

**Known incomplete cleanup:** `~/.secrets/matrix-hitl-bot.env` and `~/.secrets/matrix-hitl-bot.yml`
are both still present on disk (the `.env` was last touched 2026-09-27, around the retirement
date). Neither is loaded by anything live — no process reads them — but they haven't been swept
up. If a future HITL-notification bot is built, do not assume these files' tokens are still
valid; scoped-mcp's own `SCOPED_MCP_HITL_TOKEN` model this bot depended on was itself retired by
the same build in favor of signed approval statements.

Matrix notification of a pending approval still happens — `notify.type: matrix` in the agent
manifest posts to the requesting agent's own room, same as before. What's gone is the *reply to
approve* half; Ted reads the notification and approves from a terminal instead.

## What it was

- **Source:** `~/repos/gitea/host-forge-matrix-hitl-bot/` (private, Gitea
  `host-forge/matrix-hitl-bot`)
- **PM2 name:** `matrix-hitl-bot`; no listening port — outbound only, to the Matrix homeserver
  and to loopback scoped-mcp
- **Fronted agents:** a static agent → room → scoped-mcp-base-url map
  (`~/.secrets/matrix-hitl-bot.yml`) covering research, developer, sysadmin, security and writer,
  each with its own `SCOPED_MCP_HITL_TOKEN`-bearing scoped-mcp HTTP process
- **Commands:** `approve[/deny] [<approval_id>]`, `pending`/`hitl`, `help` — only from an
  authorized mxid (`AUTHORIZED_MXIDS`) in a configured agent room, with an explicit leading verb
  (no conversational "yes"/"ok"/"lgtm" trigger)
- **Security properties:** no secret ever reached the requesting agent (replies carried only
  approval id, tool name and decision); per-agent bearer isolation; mandatory mxid-based sender
  authentication; a startup-timestamp guard against replaying an old `approve` from room
  scrollback; fail-closed on an unreachable or `503` endpoint

## Related Docs

- [scoped-mcp.md](scoped-mcp.md) — the current signed, terminal-only HITL approval flow this bot
  used to front
- [harlock.md](harlock.md) — a prior decommission record in the same style
- [matrix-dispatcher.md](matrix-dispatcher.md) — routes operator chat to agent sessions (separate
  bot, unaffected by this retirement)
- [matrix-admin-bot.md](matrix-admin-bot.md) — provisions bot accounts and room membership
- [dragonfly.md](dragonfly.md) — HITL state backend scoped-mcp still uses for pending approvals
