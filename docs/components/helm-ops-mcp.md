# helm-ops MCP

helm-ops is an SSH-based MCP server for the helm-build agent. It provides remote shell execution and filesystem operations on the Helm target host (a second mini PC running the platform build), plus read-only local access to build plans and memory on claudebox.

It sits alongside [homelab-ops](homelab-ops-mcp.md) in [Layer 1](../../README.md#layer-1--host--core-tooling) — same tool surface, different transport. Where homelab-ops runs locally on claudebox via HTTP, helm-ops tunnels the same operations to the remote build machine over SSH.

## Why a Separate Server

Building the Helm platform happens on a second machine. The helm-build agent runs on claudebox and needs to execute commands, read files, and write configs on the remote host as if it were local. helm-ops makes that transparent — the agent calls the same tool names (`run_command`, `read_file`, `write_file`) regardless of which host it's targeting.

The local read-only tools give the helm-build agent access to build plans, design docs, and memory on claudebox without needing a second connection.

## Tools

### Remote (Helm host via SSH)

| Tool | Description |
|------|-------------|
| `run_command` | Execute a bash command on the remote host. Returns stdout/stderr/exit_code. |
| `read_file` | Read a file by absolute path, with optional line range. |
| `write_file` | Write or overwrite a file. Creates parent directories automatically. |
| `edit_file` | Find-and-replace edit — old string must match exactly once. |
| `read_directory` | List directory contents, optionally recursive. |
| `upload_file` | SCP a file from claudebox to the remote host. |

### Local (claudebox, read-only)

| Tool | Description |
|------|-------------|
| `local_read_file` | Read build plans, design docs, and memory files on claudebox. |
| `local_read_directory` | List build plan and memory directories on claudebox. |

Local tools are restricted to an allowlist: the helm-platform repo, helm-build project dir, research build plans, memory, and the prime-directive repo. No writes.

## Runtime

- **PM2 service:** `helm-ops-mcp` (always-on)
- **Port:** 8283 (streamable-HTTP, localhost only)
- **Transport:** Streamable HTTP to Claude Code; SSH to the remote host

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HELM_SSH_HOST` | *(required)* | Remote host IP or hostname |
| `HELM_SSH_USER` | `ted` | SSH username |
| `HELM_SSH_KEY` | `~/.ssh/id_ed25519` | Path to SSH private key |
| `HELM_SSH_PORT` | `22` | SSH port |
| `HELM_SSH_TIMEOUT` | `60` | Default command timeout (seconds) |

Claude Code `settings.json`:
```json
{
  "helm-ops": {
    "type": "url",
    "url": "http://localhost:8283/mcp"
  }
}
```

## Prerequisites

- SSH key-based auth configured from claudebox to the remote build machine
- Python 3.10+ with `fastmcp` installed on claudebox
- Remote host must have Debian installed with SSH enabled

## Security

helm-ops provides unrestricted shell access to the remote host via SSH. It is designed for trusted internal use only — the helm-build agent running on claudebox. Do not expose port 8283 externally.

## Relationship to homelab-ops

| | homelab-ops | helm-ops |
|---|---|---|
| Target | claudebox (local) | Helm host (remote via SSH) |
| Transport | HTTP → localhost process | HTTP → SSH → remote |
| Write access | Full | Full (remote) + read-only (local) |
| Use case | All agents on claudebox | helm-build agent only |

## Related Docs

- [homelab-ops MCP](homelab-ops-mcp.md) — the local equivalent for claudebox
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — service definition
