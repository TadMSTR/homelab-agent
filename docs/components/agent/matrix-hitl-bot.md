# matrix-hitl-bot (forge)

Matrix front end for scoped-mcp's in-session HITL approval flow (SMCP-14 Phase C). When an
agent calls a HITL-gated tool, scoped-mcp rejects the call and posts an "approval required"
prompt into the agent's own notify room. This bot lets the operator approve or deny by
replying in that room — it authenticates the sender, resolves the room to that agent's
scoped-mcp HTTP endpoint, and calls `/hitl/approve` or `/hitl/deny` with the right per-agent
bearer token.

**The requesting agent is never in the loop.** It never sees a token and never calls the
approve endpoint itself — the old workaround of an agent self-approving its own gated call
via `system-ops` is what this removes.

- **Source:** `~/repos/personal/matrix-hitl-bot/` (private, Gitea `host-forge/matrix-hitl-bot`)
- **PM2 name:** `matrix-hitl-bot`
- **Port:** none — outbound only, to the Matrix homeserver and to loopback scoped-mcp
- **Status:** online

## How It Works

```
agent → gated tool call
      → scoped-mcp rejects, posts prompt to the agent's notify room, stores pending approval
Ted   → replies "approve" in that room
bot   → authenticates Ted, resolves room → agent → scoped-mcp base URL, GET /hitl/pending
      → POST /hitl/approve {approval_id}  (Bearer <that agent's SCOPED_MCP_HITL_TOKEN>)
      → posts ack: "Approved developer.abc123… — github_pr_merge"
agent → retries; scoped-mcp middleware consumes the pre-approval token; call runs
```

## Fronted Agents

The bot holds a per-agent bearer and a static agent → room → scoped-mcp-base-url map
(`config.example.yml`, deployed as `~/.secrets/matrix-hitl-bot.yml`) — one entry per forge
resident agent's scoped-mcp HTTP process:

| Agent | scoped-mcp base | Notify room |
|-------|-----------------|-------------|
| research | `http://127.0.0.1:8471` | `!<room>:helmforge.me` (research) |
| developer | `http://127.0.0.1:8472` | `!<room>:helmforge.me` (developer) |
| sysadmin | `http://127.0.0.1:8473` | `!<room>:helmforge.me` (sysadmin) |
| security | `http://127.0.0.1:8474` | `!<room>:helmforge.me` (security) |
| writer | `http://127.0.0.1:8475` | `!<room>:helmforge.me` (writer) |

Endpoint resolution is deliberately a static config file, not the agent-postgres session
registry — the per-agent scoped-mcp processes and ports are fixed and long-lived under PM2,
and the bot needs a per-agent bearer token regardless (the registry doesn't hold one), so a
config file is required either way. Registry-based resolution is the documented
generalization for a future ephemeral/clone-pool session model, where ports aren't known
ahead of time.

## Commands

Only messages from an authorized sender (`AUTHORIZED_MXIDS`, default `@ted:helmforge.me`) in
a configured agent room are acted on — everything else is ignored silently, since the bot
shares these rooms with normal agent/operator conversation. Only an explicit leading verb
triggers it; conversational "yes"/"ok"/"lgtm" do **not** approve anything.

| Reply | Effect |
|-------|--------|
| `approve` | Approve the single pending call for this room's agent (asks if more than one) |
| `approve <approval_id>` | Approve a specific approval id |
| `deny` / `deny <approval_id>` | Deny it |
| `pending` (or `hitl`) | List this agent's pending approvals |
| `help` | Usage |

`approve` / `deny` may be `!`-prefixed (`!approve`) if you prefer explicit command syntax.

## Configuration

Two parts: a non-secret agent map (YAML) and secret tokens (env).

- **`HITL_CONFIG_FILE`** (default `~/.secrets/matrix-hitl-bot.yml`) — the agent map above:
  `agent_id`, `room_id`, `base_url`, and `token_env` (the name of the env var holding that
  agent's `SCOPED_MCP_HITL_TOKEN`).
- **`ENV_FILE`** (default `~/.secrets/matrix-hitl-bot.env`) — `MATRIX_HOMESERVER_URL`,
  `MATRIX_ACCESS_TOKEN` (bot account, provisioned via matrix-admin-bot), `MATRIX_BOT_USER_ID`
  (default `@forge-hitl:helmforge.me`), `AUTHORIZED_MXIDS`, and one `HITL_TOKEN_<AGENT>` per
  fronted agent — each must match that agent's `scoped-mcp` `SCOPED_MCP_HITL_TOKEN`.

The bot fails fast at startup on any missing token or malformed config — a half-configured
bot that silently no-ops is worse than one that refuses to start.

## Security Properties

- **No secret ever reaches the requesting agent.** Bot replies carry only the approval id,
  tool name, and decision — all already visible in scoped-mcp's own room prompt. The OTP
  used by the deferred Phase 2 courier path is never routed through this bot.
- **Per-agent bearer isolation.** Each agent's scoped-mcp process has its own
  `SCOPED_MCP_HITL_TOKEN`. The bot holds all of them and presents the right one per room;
  agents hold none.
- **Sender authentication is mandatory**, enforced by mxid — not socially.
- **No history replay.** On restart the sync token is primed before the message callback is
  registered, and a startup-timestamp guard drops stale events, so an old `approve` in room
  scrollback can never re-approve anything.
- **Fail-closed UX.** If the endpoint is unreachable or returns `503`, the bot says so and
  states plainly that nothing changed — it never implies an approval happened.

## Dependencies

- **Depends on:** [scoped-mcp.md](scoped-mcp.md) — each fronted agent's scoped-mcp process
  must be running under `--transport http` with `SCOPED_MCP_HITL_TOKEN` set and the matching
  `HITL_TOKEN_<AGENT>` value in the bot's env file; [synapse.md](synapse.md) — the forge
  Matrix homeserver.
- **Depended on by:** none — this is the terminal step in the HITL approval chain (operator
  UX), not a dependency of any other forge service.

## Operations

- **Logs:** `~/.pm2/logs/matrix-hitl-bot-{out,error}.log`
- **Restart:** `pm2 restart matrix-hitl-bot` — required after rotating any `HITL_TOKEN_<AGENT>`
  value or editing the agent map.
- **Health check:** `pending` (or `hitl`) in any fronted agent's room should return a
  (possibly empty) list without error. A silent bot after restart usually means a missing or
  unreadable `ENV_FILE`/`HITL_CONFIG_FILE`.

## scoped-mcp Integration

Not itself an MCP server — it is a Matrix-facing client of each agent's scoped-mcp `/hitl/*`
HTTP routes (see [scoped-mcp.md](scoped-mcp.md)). No agent has this bot in its own tool
surface; it runs as an independent PM2 service acting entirely on the operator's behalf.

## Related Docs

- [scoped-mcp.md](scoped-mcp.md) — HITL gate, `/hitl/approve`/`/hitl/deny`/`/hitl/pending`
  routes, `SCOPED_MCP_HITL_TOKEN`
- [matrix-dispatcher.md](matrix-dispatcher.md) — routes operator chat to agent sessions
  (separate bot; matrix-hitl-bot handles only approve/deny)
- [matrix-admin-bot.md](matrix-admin-bot.md) — provisions bot accounts and room membership
- [dragonfly.md](dragonfly.md) — HITL state backend scoped-mcp uses for the pending
  approval and OTP records this bot resolves
