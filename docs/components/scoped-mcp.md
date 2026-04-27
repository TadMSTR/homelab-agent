# scoped-mcp

Per-agent scoped MCP tool proxy. One server process per agent — loads only the tools that agent is allowed to use, enforces resource boundaries between agents, holds credentials so agents never see them, and logs every tool call to a structured audit trail.

**Version:** 0.4.0 | **PyPI:** [`scoped-mcp`](https://pypi.org/project/scoped-mcp/) | **Source:** [TadMSTR/scoped-mcp](https://github.com/TadMSTR/scoped-mcp)

## The Problem

Multi-agent setups share MCP servers. Every agent sees every tool. Agent A can read Agent B's files, write to Agent B's database, and send alerts from Agent B's ntfy topic. Credentials are exposed to all agents. Audit logs are fragmented.

scoped-mcp solves this with a proxy layer: each agent gets its own server process that loads only the modules its manifest allows, enforces resource boundaries (Agent A's filesystem path is not Agent B's), injects credentials so agents never receive token values, and wraps every tool call in a structured audit log entry.

## Architecture

```
Agent process (AGENT_ID=research-01, AGENT_TYPE=research)
    │
    ▼ MCP (stdio)
┌─────────────────────────────────────────┐
│  scoped-mcp (one process per agent)     │
│                                         │
│  ① Load manifest for AGENT_TYPE         │
│  ② Register allowed tool modules        │
│  ③ Inject credentials into modules      │
│  ④ Every tool call:                     │
│     → enforce resource scope            │
│     → execute tool logic                │
│     → write audit log entry             │
└─────────────────────────────────────────┘
    │           │           │
    ▼           ▼           ▼
 Backend A   Backend B   Backend C
 (scoped)    (scoped)    (scoped)
```

Key design decisions:
- **One process per agent** — no shared state between agent sessions
- **Manifest is the source of truth** — unlisted modules never load
- **Scope enforcement before backend calls** — a scope violation raises before any I/O
- **Credentials never leave the proxy** — agents receive tool results, not token values

## Wiring to an Agent

### Manifest format

Create a manifest YAML for each agent type:

```yaml
# manifests/research-agent.yml
agent_type: research
description: "Read-only research agent"

modules:
  filesystem:
    mode: read              # read-only: read_file + list_dir only
    config:
      base_path: /data/agents  # PrefixScope adds /{agent_id}/ automatically

  sqlite:
    mode: read
    config:
      db_dir: /data/sqlite  # each agent gets /data/sqlite/agent_{agent_id}.db

  ntfy:                     # write-only — no mode field needed
    config:
      topic: "research-{agent_id}"
      max_priority: high

credentials:
  source: env               # reads NTFY_TOKEN etc. from environment
  # or: source: file, path: /run/secrets/agent.yml
```

The `mode` field controls which tools register:
- `mode: read` — read-decorated tools only (e.g. `filesystem_read_file`, `filesystem_list_dir`)
- `mode: write` — both read and write tools
- Notification modules are write-only by design — no `mode` field needed
- **`mcp_proxy` ignores `mode` entirely** — use `tool_allowlist`/`tool_denylist` in config instead

The `type` field enables multiple instances of the same module class under different manifest keys. Required when proxying more than one upstream MCP server:

```yaml
modules:
  task-queue:
    type: mcp_proxy
    config:
      url: http://127.0.0.1:8485/mcp

  memory-search:
    type: mcp_proxy
    config:
      url: http://127.0.0.1:8486/mcp
      tool_allowlist: [search_memory]
```

Without `type:`, the manifest key is used as the class name (existing behaviour — all manifests without `type:` are unchanged).

### Claude Code `settings.json`

```json
{
  "mcpServers": {
    "tools": {
      "command": "scoped-mcp",
      "args": ["--manifest", "manifests/research-agent.yml"],
      "env": {
        "AGENT_ID": "research-01",
        "AGENT_TYPE": "research"
      }
    }
  }
}
```

`AGENT_ID` is the unique instance identifier (used for resource scoping). `AGENT_TYPE` selects the manifest. Multiple agent instances of the same type share a manifest but get separate resource namespaces via `AGENT_ID`.

### Installation

```bash
# Core modules only (filesystem, sqlite, notifications)
pip install scoped-mcp

# With HTTP client modules (http_proxy, grafana, influxdb, ntfy, matrix, slack, discord)
pip install "scoped-mcp[http]"

# Everything
pip install "scoped-mcp[all]"
```

## Module Reference

### Storage

| Module | Scope | Read tools | Write tools |
|--------|-------|-----------|-------------|
| `filesystem` | `PrefixScope` — `agents/{agent_id}/` under `base_path` | `read_file`, `list_dir` | `write_file`, `delete_file` |
| `sqlite` | Per-agent DB file — `{db_dir}/agent_{agent_id}.db` | `query`, `list_tables` | `execute`, `create_table` |

### Notifications (write-only)

Notification modules are write-only by design — every agent needs to send alerts, but no agent should see webhook URLs, SMTP passwords, or API tokens.

| Module | Backend | Credential | Scope |
|--------|---------|------------|-------|
| `ntfy` | ntfy.sh (self-hosted or cloud) | Server URL + optional token | Topic per agent (`{agent_id}` template) |
| `smtp` | Any SMTP server | Host, port, user, password | Configured sender + allowed recipients |
| `matrix` | Matrix homeserver | Access token | Room allowlist |
| `slack_webhook` | Slack incoming webhook | Webhook URL | One webhook = one channel |
| `discord_webhook` | Discord webhook | Webhook URL | One webhook = one channel |

### Infrastructure

| Module | Scope | Read tools | Write tools |
|--------|-------|-----------|-------------|
| `http_proxy` | Service allowlist + SSRF prevention | `get` | `post`, `put`, `delete` |
| `grafana` | Folder-based (`agent-{agent_id}/`) | `list_dashboards`, `get_dashboard`, `query_datasource`, `list_datasources` | `create_dashboard`, `update_dashboard`, `create_alert_rule`, `delete_dashboard` |
| `influxdb` | Bucket allowlist + `NamespaceScope` | `query`, `list_measurements`, `get_schema` | `write_points`, `create_bucket`, `delete_points` |

### MCP Proxy

`mcp_proxy` is a built-in module that proxies any existing MCP server through scoped-mcp without writing custom Python. Tools are discovered at startup via `tools/list` and forwarded per-call. Supports HTTP (streamable-http) and stdio transports.

```yaml
modules:
  task-queue:
    type: mcp_proxy
    config:
      url: http://127.0.0.1:8485/mcp   # streamable-http upstream

  # stdio example — stateless, lightweight servers only
  # Each tool call spawns a fresh subprocess; avoid for persistent servers
  some-local-tool:
    type: mcp_proxy
    config:
      command: /usr/local/bin/python3
      args: [/path/to/stateless_server.py]
```

| Config key | Type | Default | Description |
|------------|------|---------|-------------|
| `url` | string | — | HTTP streamable-http endpoint (mutually exclusive with `command`) |
| `command` | string | — | Executable for a stdio server (mutually exclusive with `url`) |
| `args` | list[str] | `[]` | Arguments passed to `command` |
| `tool_allowlist` | list[str] | `[]` | If non-empty, only these upstream tools are exposed |
| `tool_denylist` | list[str] | `[]` | These tools are always hidden (applied after allowlist) |
| `discovery_timeout_seconds` | float | `10.0` | Timeout for connecting to the upstream server at startup |

No additional install extras required — `mcp_proxy` ships with the base `scoped-mcp` package.

## Scope Strategies

Three reusable strategies for resource isolation:

| Strategy | How it works | Used by |
|----------|-------------|---------|
| `PrefixScope` | Prepends `/{agent_id}/` to paths/keys; rejects traversal attempts | `filesystem`, `http_proxy` |
| `NamespaceScope` | Prefixes key-value keys with `{agent_id}:` | `influxdb` |
| Allowlist | Config holds explicit set of allowed resources | `grafana` (folders), `smtp` (recipients), `matrix` (rooms) |
| Per-file | Each agent gets a separate database file | `sqlite` |

Scope enforcement always runs before any backend call. A scope violation raises before any I/O.

## Audit Log

Every tool call is logged as a structured JSON entry:

```json
{
  "ts": "2026-04-18T10:23:01Z",
  "agent_id": "research-01",
  "agent_type": "research",
  "tool": "filesystem_read_file",
  "args": {"path": "report.md"},
  "resolved_path": "/data/agents/research-01/report.md",
  "result_bytes": 4200,
  "duration_ms": 3
}
```

Emits to stdout and/or a log file. All entries include timing — useful for spotting slow backends or runaway tool loops.

## Writing a Custom Module

```python
# src/scoped_mcp/modules/redis.py
from scoped_mcp.modules._base import ToolModule, tool
from scoped_mcp.scoping import NamespaceScope

class RedisModule(ToolModule):
    name = "redis"
    scoping = NamespaceScope()
    required_credentials = ["REDIS_URL"]

    @tool(mode="read")
    async def get_key(self, key: str) -> str | None:
        """Get a value (scoped to agent namespace)."""
        scoped_key = self.scoping.apply(key, self.agent_ctx)
        return await self._redis.get(scoped_key)

    @tool(mode="write")
    async def set_key(self, key: str, value: str, ttl: int = 0) -> bool:
        """Set a key-value pair (scoped to agent namespace)."""
        scoped_key = self.scoping.apply(key, self.agent_ctx)
        return await self._redis.set(scoped_key, value, ex=ttl or None)
```

Add the module to a manifest:

```yaml
modules:
  redis:
    mode: read
    config: {}
```

See `examples/custom-module/` in the repo and `docs/module-authoring.md` for the full contract.

## Full Reference

[TadMSTR/scoped-mcp README](https://github.com/TadMSTR/scoped-mcp) — complete API reference, quickstart, comparison table, non-goals, and multi-agent setup examples.

**Security disclosures:** scoped-mcp has a formal security policy ([SECURITY.md](https://github.com/TadMSTR/scoped-mcp/blob/main/SECURITY.md)) covering scope bypass, credential isolation failures, and path traversal. Use the GitHub private advisory channel or the project email rather than opening a public issue.
