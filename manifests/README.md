# Agent Manifests

Sanitized example manifests for the five forge agents. Each manifest defines the agent's scoped tool surface — what MCP servers it can reach, what tools within each server it can call, rate limits, HITL gates, argument filters, and workspace access rules.

## Files

| File | Agent | Role |
|------|-------|------|
| `sysadmin-agent.yml.example` | sysadmin | Infrastructure ops — Docker, apt, PM2, service diagnostics |
| `research-agent.yml.example` | research | Research and build planning — search, docs, handoffs |
| `developer-agent.yml.example` | developer | Code — MCP servers, scripts, config, PRs |
| `writer-agent.yml.example` | writer | Documentation — READMEs, runbooks, component docs |
| `security-agent.yml.example` | security | Security audits, triage, remediation verification |

## How Manifests Work

scoped-mcp reads the manifest at agent startup and creates a filtered MCP proxy. The agent connects to scoped-mcp as its sole MCP provider; scoped-mcp routes calls to the real backend services.

```
Agent
  │
  └── scoped-mcp (reads manifest)
        │
        ├── system-ops      http://localhost:8282/mcp
        ├── githost-mcp     subprocess (run-githost-mcp-<agent>.py)
        ├── searxng-mcp     subprocess (run-searxng-mcp.sh)
        ├── qmd             http://localhost:8181/mcp
        ├── task-queue-mcp  http://localhost:8485/mcp
        └── ...             (tool_denylist/allowlist applied per module)
```

No credentials appear in the manifest as literal values. All secrets are referenced as `${ENV_VAR}` and sourced from Vault at startup.

## Manifest Schema Reference

Key sections in each manifest:

### `modules`

Each module is an MCP server the agent can reach:

```yaml
modules:
  searxng-mcp:
    type: mcp_proxy
    config:
      command: /path/to/run-searxng-mcp.sh   # subprocess launch
      # OR
      url: http://localhost:8181/mcp          # HTTP transport
      tool_denylist:                          # blocked tools
        - clear_cache
      tool_allowlist:                         # if set, ONLY these tools are allowed
        - search
        - fetch_url
      headers:                               # injected headers (for auth)
        Authorization: "Bearer ${TOKEN}"
```

### `hitl`

Human-in-the-loop gates — tools that require operator approval before execution:

```yaml
hitl:
  timeout_seconds: 300
  approval_required:
    - dockhand-mcp_stack_action
    - patchmon-mcp_approve_patch_run
  notify:
    type: matrix
    room: "<room-id>"
```

### `argument_filters` / `response_filters`

Pattern-based filters applied to all tool calls and responses:

```yaml
argument_filters:
  - name: "credential-leak"
    pattern: "(password|secret|api[_.]?key)"
    fields: ["*"]
    action: warn   # or block
```

### `rate_limits`

Per-tool and global rate limiting:

```yaml
rate_limits:
  global: "60/minute"
  per_tool:
    "dockhand-mcp_container_action": "10/minute"
```

### `workspace_access`

Directories the agent can read or write:

```yaml
workspace_access:
  - path: ~/docker/
    access: readwrite
    git_backed: true
    branch_required: false
```

## Sanitization

These examples have had the following replaced:
- `192.168.1.x` → `<server-ip>`
- Matrix room IDs (`!<hash>:helmforge.me`) → `<room-id>`
- All credential values remain as `${ENV_VAR}` references (no real values were present)

Replace `<room-id>` with your actual Matrix room IDs and `<server-ip>` with your server's LAN IP before deploying.

## Deployment

See [`docs/components/scoped-mcp.md`](../docs/components/scoped-mcp.md) for the full deployment guide including PM2 config, environment setup, and Vault integration.
