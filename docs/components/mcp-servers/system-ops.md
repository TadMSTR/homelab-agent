# system-ops

system-ops (internally `homelab-ops-mcp`) is a FastMCP Python server providing shell
command execution, file system read/write access, and process inspection on the forge
host. It gives agents direct local system access, scoped per agent via manifests.

- **Package:** `homelab-ops-mcp` (TadMSTR/homelab-ops-mcp)
- **Repo:** `/home/ted/repos/personal/homelab-ops-mcp/`
- **Transport:** streamable-http — `127.0.0.1:8282`
- **Runtime:** Python 3.10+

## Tools (6)

| Tool | Description |
|------|-------------|
| `run_command` | Execute shell commands via `bash -c`; returns stdout, stderr, exit_code |
| `read_file` | Read file contents with optional line range |
| `write_file` | Write/overwrite files; creates parent directories by default |
| `edit_file` | Find-and-replace editing (old_str must match exactly once) |
| `read_directory` | List directory contents, optionally recursive with max_depth |
| `list_processes` | List running processes sorted by CPU/memory/PID with optional name filter |

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `--host` | No | `127.0.0.1` | Bind address (CLI arg) |
| `--port` | No | `8282` | Listen port (CLI arg) |

No external env vars required. Host, port, and working directory are configurable via
CLI arguments. Default working directory is `/home/ted`.

## Dependencies

- Python 3.10+ with `fastmcp>=3.3.1` and `psutil>=7.2.2`

## Launch

PM2 process named `system-ops`, configured via `ecosystem.config.js` in the repo root:

```js
args: ["server.py", "--host", "127.0.0.1", "--port", "8282"]
```

Logs to `/home/ted/logs/system-ops.log`.

## scoped-mcp Wiring

| Manifest | Access | Rate limit |
|----------|--------|------------|
| `sysadmin-agent.yml` | Full access | Unrestricted |
| `developer-agent.yml` | Full access | 60/min |
| `security-agent.yml` | All except `edit_file` | 30/min |
| `writer-agent.yml` | All except `list_processes` | 20/min |
| `research-agent.yml` | No access | — |

All manifests register it as `mcp_proxy` type pointing to `http://localhost:8282/mcp`.

## Security Notes

- Binds to localhost only — no external network exposure
- No authentication (local agent use only)
- Full shell access via `run_command` — security boundary enforced at scoped-mcp manifest level
- File write operations create parent directories automatically; agents must be trusted
- Security agent has `edit_file` denied to prevent modification of audited files

## Known Issue: No `~` Expansion

`read_file`, `write_file`, `edit_file`, and `read_directory` do not expand a leading `~`
in paths. A path like `~/notes/example.md` is resolved against the server's own working
directory, which creates (or reads/writes under) a literal `~` directory rather than the
caller's home directory — and the call still returns a success result, so the failure is
silent. This affects every agent with system-ops access, not just one. Always pass
absolute paths (`/home/<user>/...`) when calling these tools.
