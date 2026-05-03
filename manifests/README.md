# Scoped-MCP Manifests

Template manifests for the headless `claude -p` projects in the build pipeline. Each manifest defines the exact tool surface available to a headless session — only the MCP modules listed are accessible.

These are framework templates. They use `<FILL_AT_DEPLOY>` placeholders for all environment-specific values (server URLs, executable paths). When deploying, copy them to `~/.claude/manifests/` and fill in the values for your setup.

## What's Here

| Manifest | Headless Agent | Tool Surface |
|----------|----------------|-------------|
| `headless-smoke-test.yml` | smoke-test | homelab-ops (run/read/write), matrix (send), task-queue (update/get) |
| `headless-skill-validator.yml` | skill-validator | homelab-ops (read/write), task-queue (update/get) |
| `headless-plane-updater.yml` | plane-updater, docs-build | homelab-ops (read/write), plane (update/comment/search), matrix (send), task-queue, agent-bus (log) |
| `headless-security-precheck.yml` | security-kb-precheck | homelab-ops (read/write) only — intentionally no Matrix, no task-queue |
| `headless-security-audit.yml` | security (headless mode) | homelab-ops (read/write/run), matrix (send), task-queue (submit/update/get), agent-bus (log) |
| `headless-context-preloader.yml` | context-preloader | homelab-ops (read/read-dir/write), task-queue (update/get) |

The tool allowlists are intentionally narrow. A skill-validator session cannot call `run_command`. A security-kb-precheck session has no network tools at all. The allowlist is the security boundary — not CLAUDE.md instructions, not trust.

## Manifest Format

```yaml
agent_type: <identifier>
description: "<one-line purpose>"

modules:
  <module-name>:
    type: mcp_proxy
    config:
      url: <URL>            # for HTTP MCP servers
      # OR
      command: <executable> # for stdio MCP servers
      args: [<arg1>, ...]   # args for stdio command
      tool_allowlist:
        - <tool_name>
        - <tool_name>
```

`type: mcp_proxy` is the standard module type — it wraps any existing MCP server (HTTP or stdio) and exposes only the listed tools. See the [scoped-mcp docs](../docs/components/scoped-mcp.md) for the full module type reference and advanced options (middleware, rate limits, HITL approval gates).

## Deploying

### Step 1 — Copy templates to local manifests dir

```bash
mkdir -p ~/.claude/manifests
cp manifests/*.yml ~/.claude/manifests/
```

### Step 2 — Fill in `<FILL_AT_DEPLOY>` values

Each placeholder comment shows the expected value for a standard homelab-agent setup:

| Placeholder context | Typical value |
|--------------------|---------------|
| `homelab-ops` url | `http://localhost:8282/mcp` |
| `matrix` url | `http://127.0.0.1:8487/mcp` |
| `task-queue` url | `http://127.0.0.1:8485/mcp` |
| `plane` command | path to plane-mcp-server executable |
| `agent-bus` command + args | path to agent-bus venv python3, then server.py |

Edit each file in `~/.claude/manifests/` and replace every `<FILL_AT_DEPLOY>` with the real value. Your local paths may differ — check `pm2 list` and `pm2 show <service>` for running MCP server addresses.

### Step 3 — Validate

```bash
# Replace with actual path to scoped-mcp
~/.venv/bin/scoped-mcp validate --manifest ~/.claude/manifests/headless-smoke-test.yml
```

Repeat for each manifest. Validation checks that the referenced servers are reachable and the tool names in the allowlist exist on the server. Fix any errors before wiring the headless projects.

### Step 4 — Wire headless project settings.json

For each headless project directory (`~/.claude/projects/<name>/`), create or update `settings.json`:

```json
{
  "mcpServers": {
    "scoped-mcp": {
      "command": "uvx",
      "args": ["scoped-mcp", "--manifest", "/home/<user>/.claude/manifests/<agent-type>.yml"]
    }
  }
}
```

Setting `mcpServers` in the project `settings.json` overrides (not merges) the global `mcpServers` — so the headless session gets only the scoped tool surface. Verify with:

```bash
claude --project <name> --bare -p "list your available tools"
```

Confirm only the expected scoped tools appear and no global tools bleed through.

## Security Model

`~/.claude/manifests/` is local config — never commit it, never push it. It contains filled-in server URLs and executable paths that may vary between deployments. The templates in this directory are safe to commit because all sensitive values are replaced with `<FILL_AT_DEPLOY>`.

The narrow allowlists mean a compromised or misbehaving headless session is limited to the tool surface it needs. A smoke-test session that goes wrong cannot call Plane tools. A skill-validator cannot execute shell commands. The manifest is the enforcement point — scoped-mcp validates every inbound tool call against it before forwarding.

## Related Docs

- [Build Pipeline Agents](../docs/components/build-pipeline-agents.md) — agent purposes, invocation map, blocked.md protocol
- [scoped-mcp](../docs/components/scoped-mcp.md) — full manifest schema, module types, middleware, HITL gates
