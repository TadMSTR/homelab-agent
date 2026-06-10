# scoped-mcp (forge)

scoped-mcp on forge is a per-agent MCP tool proxy giving each of the 5 forge resident
agents (sysadmin, research, developer, writer, security) an isolated, manifest-controlled
tool surface. Each agent session launches its own scoped-mcp process; the proxy loads only
the modules the agent is allowed to use and injects credentials so agents never see token
values directly.

See [homelab-agent scoped-mcp doc](../../../homelab-agent/docs/components/scoped-mcp.md) for
the general architecture. This doc covers the forge-specific deployment.

- **Package:** `scoped-mcp` v1.2.2 (installed at `/opt/venvs/scoped-mcp/`; `pip show scoped-mcp` reports 1.2.2)
- **Venv:** `/opt/venvs/scoped-mcp/`
- **Manifests:** `~/.claude/manifests/<agent>-agent.yml`
- **Transport:** stdio (launched by Claude Code settings.json)

## Installation

scoped-mcp is pre-installed in a shared venv. Install from git tag (PyPI lags behind):

```bash
python3 -m venv /opt/venvs/scoped-mcp
/opt/venvs/scoped-mcp/bin/pip install "git+https://github.com/TadMSTR/scoped-mcp.git@v1.2.2"
```

To upgrade an existing venv:

```bash
/opt/venvs/scoped-mcp/bin/pip install --force-reinstall "git+https://github.com/TadMSTR/scoped-mcp.git@v1.2.2"
```

## Agent File Layout

Agent platform files are maintained in source repos and symlinked into place. Always edit the source repo — never the symlink target.

| Symlink path | Source repo | Local clone |
|-------------|-------------|-------------|
| `~/.claude/projects/<agent>/CLAUDE.md` | `agent-platform-agents` | `~/repos/gitea/agent-platform-agents/<agent>/CLAUDE.md` |
| `~/.claude/skills/<skill>/SKILL.md` | `agent-platform-skills` | `~/repos/gitea/agent-platform-skills/<skill>/SKILL.md` |
| `~/.claude/manifests/<type>-agent.yml` | `host-forge-scripts` | `~/repos/gitea/host-forge-scripts/manifests/<type>-agent.yml` |

All three repos commit directly to main. Run `qmd update && qmd embed` for the relevant collection after changing CLAUDE.md or skill files (QMD indexes these for agent retrieval).

## Session Wiring

scoped-mcp is launched differently for interactive vs headless sessions.

### Interactive sessions (Claude Code desktop/terminal)

Each agent's `settings.json` at `~/.claude/projects/<agent>/.claude/settings.json` wires
scoped-mcp using the **full venv path**:

```json
{
  "mcpServers": {
    "scoped-mcp": {
      "type": "stdio",
      "command": "/opt/venvs/scoped-mcp/bin/scoped-mcp",
      "args": ["--manifest", "/home/ted/.claude/manifests/<agent>-agent.yml"]
    }
  }
}
```

### Headless sessions (`claude -p`)

Headless mode reads `.mcp.json` from the project directory, **not** `settings.json`. Each
agent has `~/.claude/projects/<agent>/.mcp.json` using the `run-scoped-mcp.sh` wrapper:

```json
{
  "mcpServers": {
    "scoped-mcp": {
      "command": "/home/ted/scripts/run-scoped-mcp.sh",
      "args": [],
      "env": {
        "AGENT_ID": "<agent>-01",
        "AGENT_TYPE": "<agent>",
        "MATRIX_HOMESERVER": "https://matrix.helmforge.me",
        "MATRIX_ACCESS_TOKEN": "<token>",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
        "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
        "OTEL_RESOURCE_ATTRIBUTES": "service.name=scoped-mcp-<agent>,agent.type=<agent>"
      }
    }
  }
}
```

`run-scoped-mcp.sh` sources `/opt/appdata/agents/<type>/.env` (Vault credentials,
Dragonfly URL) before invoking scoped-mcp. Both `AGENT_ID` and `AGENT_TYPE` are required.

## Manifest Structure

Each agent has a manifest at `~/.claude/manifests/<agent>-agent.yml`. Full Phase 7
hardened manifests include modules, denylists, rate limits, HITL (sysadmin only), audit,
argument filters, and response filters. Env var placeholders (`${VAR_NAME}`) are expanded
from the agent's `.env` file before YAML parse (v1.2.0+).

## Current Agent Tool Surfaces

| Agent | Modules | loki-mcp |
|-------|---------|----------|
| research | searxng-mcp, qmd, graphiti, memory-metadata-mcp, memory-search-mcp, task-queue-mcp, langfuse-mcp, signoz-mcp, **claudebox-ops**, matrix | — |
| sysadmin | system-ops, githost-mcp, patchmon-mcp, dockhand-mcp, searxng-mcp, qmd, memory-metadata-mcp, task-queue-mcp, pm2-mcp, grafana-mcp, loki-mcp, signoz-mcp, **claudebox-ops**, matrix | ✓ |
| security | system-ops, searxng-mcp, memory-metadata-mcp, task-queue-mcp, matrix | ✓ |
| writer | system-ops, searxng-mcp, qmd, graphiti, memory-metadata-mcp, memory-search-mcp, task-queue-mcp, matrix | — |
| developer | system-ops, githost-mcp, searxng-mcp, qmd, graphiti, memory-metadata-mcp, task-queue-mcp, langfuse-mcp, matrix | — |

## claudebox-ops (2026-05-28)

Cross-host access to claudebox (<server-ip>) via the homelab-ops-mcp instance running
there at `:8282`. Allows agents to inspect claudebox PM2 services, read configs, and run
commands without SSH.

- **Endpoint:** `http://<server-ip>:8282/mcp`
- **Tools:** `run_command`, `read_file`, `read_directory`, `list_processes` (`write_file` + `edit_file` denylisted for research)
- **Rate limit:** 30/min (research), 60/min (sysadmin)
- **research:** `write_file` and `edit_file` denylisted — read/run only
- **sysadmin:** full access (consistent with system-ops treatment on forge)

## Phase 7 Hardening (2026-05-26)

All 5 agent manifests received the following additions:

### Tool Denylists

Each manifest has a `tool_denylist` per module to enforce least-privilege:

| Agent | Denylisted tools |
|-------|-----------------|
| research | `graphiti: clear_graph`, `searxng-mcp: clear_cache` |
| developer | `graphiti: clear_graph`, `searxng-mcp: clear_cache` |
| writer | `graphiti: clear_graph`, `system-ops: list_processes`, `searxng-mcp: clear_cache` |
| security | `system-ops: edit_file`, `searxng-mcp: clear_cache` |
| sysadmin | `searxng-mcp: clear_cache` |

### Rate Limits

```yaml
rate_limits:
  global: "120/minute"        # research, developer
  global: "60/minute"         # writer, security, sysadmin
  per_tool:
    "searxng-mcp_search_and_summarize": "10/minute"   # research (LLM-intensive)
    "system-ops_run_command": "60/minute"              # developer
    "system-ops_run_command": "20/minute"              # writer
    "system-ops_run_command": "30/minute"              # security
    "dockhand-mcp_*": "10/minute"                      # sysadmin
    "patchmon-mcp_*": "5/minute"                       # sysadmin
    "pm2-mcp_*": "20/minute"                           # sysadmin
```

### HITL (sysadmin only)

The sysadmin agent requires human approval before executing high-impact tools:

```yaml
hitl:
  timeout_seconds: 300
  approval_required:
    - "dockhand-mcp_container_action"
    - "dockhand-mcp_stack_action"
    - "dockhand-mcp_update_container"
    - "patchmon-mcp_approve_patch_run"
    - "pm2-mcp_stop_service"
    - "pm2-mcp_restart_service"
  notify:
    type: matrix
    room: "!rcRDEZtSLvYSaNSfyN:helmforge.me"
```

**Approval mechanism:** Matrix is used for **notification only** (outbound POST to #forge).
Approval is via the CLI, not Matrix replies:

```bash
# List pending approvals
/opt/venvs/scoped-mcp/bin/scoped-mcp hitl list \
  --manifest ~/.claude/manifests/sysadmin-agent.yml

# Approve (must complete within 300s of the tool call)
/opt/venvs/scoped-mcp/bin/scoped-mcp hitl approve \
  --manifest ~/.claude/manifests/sysadmin-agent.yml <id>
```

The sysadmin agent is instructed (via its CLAUDE.md) to ask in-chat for approval first,
then call the tool, then immediately run the HITL list + approve commands via system-ops.
This keeps the approval round-trip well within the 300s timeout since Ted's in-chat
confirmation is the signal to proceed.

State backend (Dragonfly):
```yaml
state_backend:
  type: dragonfly
  url: "${DRAGONFLY_URL}"   # expanded from /opt/appdata/agents/sysadmin/.env
```

### Audit

All 5 agents emit tool call events to agent-bus:

```yaml
audit:
  agent_bus_emit: true
  agent_bus_comms_dir: "~/.claude/comms"
  log_args: true
```

### Argument Filters

All 5 agents have three argument filter rules:

| Rule | Pattern | Action |
|------|---------|--------|
| `credential-leak` | password/secret/api_key/bearer token patterns | `warn` |
| `path-traversal` | `../` or `..\` in path fields | **`block`** |
| `shell-injection-warn` | `rm -rf /`, `/etc/shadow`, `/etc/passwd` in command fields | `warn` |

Only `path-traversal` is a hard block. The other two are `warn` — monitor ops logs for
one week before promoting to `block`.

### Response Filters

All 5 agents have two response filter rules:

| Rule | Pattern | Action |
|------|---------|--------|
| `response-credential-leak` | API keys, GitHub tokens, AWS access key IDs, OAuth bearer tokens | `redact` |
| `response-injection-attempt` | Prompt injection patterns | `warn` |

### ed25519 Signed Audit Trail

scoped-mcp v1.1.0+ supports ed25519 signing of agent-bus audit events via
`scoped_mcp.contrib.signing_hook`. Private keys are stored in Vault KV
(`secret/data/agents/<type>`) and loaded at agent startup. Public keys are registered
in `~/.claude/comms/agent-keys.json` (chmod 644).

Vault access is via per-agent AppRoles (`forge-<type>`) with per-agent policies
(`agents-<type>-policy`) scoped to `read` on `secret/data/agents/<type>` only.
AppRole credentials are in `/opt/appdata/agents/<type>/.env` (chmod 600).

> **Current status: ACTIVE** (as of 2026-05-28). Vault is unsealed, `hvac` v2.4.0 is
> installed in the scoped-mcp venv, and all 5 agent `settings.json` files have
> `VAULT_ADDR`, `VAULT_ROLE_ID`, and `VAULT_SECRET_ID` wired. On each agent's next session
> start, scoped-mcp authenticates to Vault, fetches the signing keypair, and registers the
> ed25519 pre-call hook — all `log_event` calls are signed before forwarding to agent-bus.
> agent-bus runs in `enforce` mode: invalid signatures are rejected, unsigned events pass
> (so agents that haven't restarted yet continue logging without errors).

## Vault AppRole Setup

Each agent authenticates to Vault via a dedicated AppRole:

| Agent | AppRole | Policy | Vault path |
|-------|---------|--------|------------|
| research | `forge-research` | `agents-research-policy` | `secret/data/agents/research` |
| developer | `forge-developer` | `agents-developer-policy` | `secret/data/agents/developer` |
| writer | `forge-writer` | `agents-writer-policy` | `secret/data/agents/writer` |
| security | `forge-security` | `agents-security-policy` | `secret/data/agents/security` |
| sysadmin | `forge-sysadmin` | `agents-sysadmin-policy` | `secret/data/agents/sysadmin` |

Credentials are in `/opt/appdata/agents/<type>/.env` — chmod 600, never committed to git.

Vault is accessible on forge at `http://localhost:8200` (port 8200 published to
`127.0.0.1:8200` in docker/vault/docker-compose.yml as of 2026-05-26).

## Agent .env Files

Each agent has `/opt/appdata/agents/<type>/.env` (chmod 600):

```
VAULT_ADDR=http://localhost:8200
VAULT_ROLE_ID=<role-id>
VAULT_SECRET_ID=<secret-id>
DRAGONFLY_URL=redis://:<password>@127.0.0.1:6380   # sysadmin only
```

These are sourced by the agent's launch environment. The manifest loader expands
`${VAR_NAME}` placeholders from the process environment before parsing (v1.2.0+).

## Adding a New MCP

To add a new forge MCP to all agent manifests:

1. Deploy and start the new PM2 MCP service
2. Add an `mcp_proxy` entry to each of the 5 manifests in `~/.claude/manifests/`
3. Restart scoped-mcp for each agent (Claude Code picks up changes on next session start)

No venv rebuild needed — `mcp_proxy` entries are configuration only.

## Legacy Cleanup

`/opt/agents/*/config/scoped-mcp.json.legacy` files are dead — superseded by the YAML
manifests at `~/.claude/manifests/`. Safe to delete once confirmed no tooling references them.

## v1.2.2 Fixes (2026-05-27)

Three silent bugs corrected in this upgrade:

- **Double-prefix registry bug** — HITL `approval_required` and rate-limit `per_tool` patterns never matched any tool calls since Phase 7 was deployed. Tool names were prefixed twice internally (`dockhand-mcp_dockhand-mcp_container_action`), so every pattern silently passed. All 5 agents now correctly enforce their denylists and rate limits. The sysadmin agent will surface HITL approval prompts for the first time on high-impact tools (`dockhand-mcp_container_action`, `patchmon-mcp_approve_patch_run`, `pm2-mcp_stop_service`, etc.).
- **Agent-bus tilde expansion** — audit events were being written to `~/...` literal paths rather than expanded absolute paths. Log shippers and the agent-bus reconciler couldn't find them. Fixed in `audit.py` — events now write to `~/.claude/comms/logs/` correctly.
- **ManifestError secret suppression** — YAML parse errors and Pydantic validation failures on a manifest could include expanded env var values (e.g., a Vault secret ID) in the error message surfaced to the agent. These are now suppressed; only a generic "manifest load failed" message is returned, with detail logged at debug level.

## Known Incompatibilities

None. The fastmcp 3.x compatibility issues present in v1.0.0 were resolved in v1.0.1.

## Related Docs

- [loki-mcp.md](loki-mcp.md) — read-only Loki query MCP (security + sysadmin agents)
- [patchmon-mcp.md](patchmon-mcp.md) — apt patch management MCP
- [dockhand-mcp.md](dockhand-mcp.md) — Docker management MCP
- [langfuse-mcp.md](langfuse-mcp.md) — LLM observability MCP
- [vault.md](vault.md) — Vault AppRole auth and KV setup
- [forge-agent-setup.md](../phases/forge-agent-setup.md) — build that wired the manifests
- [forge-agent-mcp-restore.md](../phases/forge-agent-mcp-restore.md) — build that fixed the venv and completed observability wiring
