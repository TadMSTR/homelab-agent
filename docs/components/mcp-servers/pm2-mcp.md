# pm2-mcp

pm2-mcp is a FastMCP Python server that wraps the PM2 process manager, giving forge
agents structured read and limited write access to PM2 services with typed responses.
It speaks directly to `pm2 jlist`, eliminating the need for raw shell access or output
scraping.

- **Tier:** Showcase (promoted from Baseline 2026-09-09). Terminal tier for this repo —
  it publishes no installable artifact, so it cannot advance to Flagship.
- **Version:** 0.4.0, released 2026-09-10 — merged and tagged; the doc below describes
  the merged **code**, not necessarily the **running** service. Verified live: the PM2
  process's last restart predates the current `server.py`, so the deployed process is
  still on pre-0.4.0 code. A sysadmin redeploy closes this gap — check `pm2 jlist`
  restart time against `server.py`'s mtime before assuming any 0.4.0 behaviour is live.
  (0.3.2 was tagged 2026-09-09 and is deployed; 0.3.0 was the long-stale prior tag.)
- **Package:** `pm2-mcp` (TadMSTR/pm2-mcp)
- **Repo:** `/home/ted/repos/personal/pm2-mcp/`
- **Transport:** streamable-http — `127.0.0.1:8486`
- **Runtime:** Python 3.11+

Further reading in the repo rather than duplicated here: `ARCHITECTURE.md` (request flow
and the environment boundary), `docs/operations.md` (deploying, health checks, recovery),
`docs/threat-model.md` (full security posture), `docs/security-audit.md` (audit history),
`examples/` (client wiring and a worked crash-loop diagnosis).

## Tools

10 tools — 4 read, 6 write. There is deliberately no `delete` verb: re-registering a
process re-captures the calling shell's environment, which is the exact mechanism behind
vikunja#767 (below), so the destructive verb with the worst failure mode is the one least
worth automating.

| Tool | Type | Description |
|------|------|-------------|
| `list_services` | read | List all PM2 processes with status, uptime, CPU, memory |
| `get_service` | read | Detailed info for a single PM2 process by name |
| `get_logs` | read | Recent log lines for a process |
| `get_status` | read | Quick status summary (online/stopped/errored) |
| `restart_service` | write | Restart a PM2 process by name |
| `stop_service` | write | Stop a PM2 process |
| `start_service` | write | Resume a stopped process already registered in PM2 — does not register a new one |
| `reload_service` | write | Graceful reload of a PM2 process |
| `flush_logs` | write | Flush PM2 log files |
| `save` | write | Save current PM2 process list |

Write operations validate service names against the live PM2 process list before
executing; unrecognized names return `{ok: false}` without touching PM2.

## Bind address and port (v0.4.0)

`--host`/`--port` are real as of v0.4.0 (vikunja#770) — before this they were accepted by
`ecosystem.config.js` but silently ignored, since `server.py` had no argument parsing.
Precedence is **argv > `MCP_HOST`/`MCP_PORT` > `127.0.0.1:8486`**, resolved per field.

**The loopback bind is enforced in code, not merely defaulted.** A non-loopback resolved
host exits non-zero instead of starting; hostnames are refused rather than resolved
(a name can be repointed after the check passes without the process restarting). There is
deliberately no override flag.

## Environment allowlist (shadow mode)

`_clean_env` computes a named allowlist for the environment handed to the `pm2` child
(vikunja#610). **It runs in shadow mode: it logs which variables enforcement would
withhold, per `pm2` invocation, and changes nothing.** Do not describe it as enforcing.
Flipping it to `PM2_MCP_ENV_MODE=enforce` is a source change to `_ENV_MODE`'s default,
gated on vikunja#771 (enforcement has only been verified against the live daemon on read
paths, not write verbs).

As of v0.4.0 the shadow log actually reaches disk (vikunja#772) — before that,
`_configure_logging()` didn't exist, the logger had no handler, and the shadow line was
silently dropped on every call, so the feature had collected zero evidence since it
shipped.

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `MCP_HOST` | No | `127.0.0.1` | Bind address. Must resolve to loopback. |
| `MCP_PORT` | No | `8486` | Listen port |
| `PM2_MCP_ENV_MODE` | No | `shadow` | `shadow` (log-only) or `enforce` (apply the allowlist) — see above |
| `PYTHONUNBUFFERED` | No | `1` | Prevent output buffering (set in PM2 config) |

## Dependencies

- Python 3.11+ with `fastmcp>=3.2.4,<4`
- PM2 installed and available in PATH

## Launch

PM2 process named `pm2-mcp`, configured via `ecosystem.config.js` in the repo root.
Fork mode (no clustering).

**Must be started by PM2 at boot, never from an interactive shell.** `pm2 start` ships
the calling shell's whole environment to the daemon as the target app's base environment,
and `pm2 save` writes the result to disk — this is how a live `CLAUDE_CODE_OAUTH_TOKEN`
sat in a world-readable `dump.pm2` for nine days (vikunja#767, fixed v0.3.2). The shipped
`ecosystem.config.js` declares `env: {}` on purpose and must not gain a secrets loader.

**`pm2 restart` does not re-read `ecosystem.config.js`.** Code changes land on restart; a
config-file change needs `pm2 delete` + `pm2 start`, which re-captures the calling shell's
environment — exactly the operation the paragraph above warns about.

CI runs a mutation gate on the trust-boundary functions (`_clean_env`, `_run_pm2`,
`_is_loopback`) with a per-function zero-survivor floor, plus a 100% statement coverage
floor.

## scoped-mcp Wiring

| Manifest | Access |
|----------|--------|
| `sysadmin-agent.yml` | Full (read + write). Write tools HITL-gated. Rate limits: `stop_service` 5/min, `restart_service` 10/min |
| `research-agent.yml` | Read-only. Denylisted: `start_service`, `stop_service`, `restart_service`, `reload_service`, `flush_logs`, `save` |
| `developer-agent.yml` | No access |
| `security-agent.yml` | No access |
| `writer-agent.yml` | No access |

## Security Notes

- Binds to localhost only — enforced in code as of v0.4.0, not merely defaulted; see
  "Bind address and port" above
- No authentication — intentional and documented, not an oversight. See
  `docs/threat-model.md §1`
- Write operations validate process names against live PM2 list before executing
- Sysadmin write access is HITL-gated via scoped-mcp approval flow
- Environment allowlist (above) is shadow-mode only; the effective control against
  environment leakage into the `pm2` child today is the `CLAUDE*`-prefix denylist
  (vikunja#767, v0.3.2)
- Audit history: `docs/security-audit.md` — most recent pass 2026-09-10, 2 findings, both
  Info, both resolved, zero Critical/High/Medium
