# scoped-mcp

Per-agent scoped MCP tool proxy. One server process per agent — loads only the tools that agent is allowed to use, enforces resource boundaries between agents, holds credentials so agents never see them, and logs every tool call to a structured audit trail.

**Version:** 1.0.0 | **PyPI:** [`scoped-mcp`](https://pypi.org/project/scoped-mcp/) | **Source:** [TadMSTR/scoped-mcp](https://github.com/TadMSTR/scoped-mcp)

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
│     → run middleware chain              │
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
  # or: source: vault (see Vault Credentials section below)

# Optional: pluggable state backend (required for rate limiting and HITL)
state_backend:
  type: in_process          # default — no external deps
  # type: dragonfly
  # url: redis://127.0.0.1:6379/0

# Optional: sliding-window rate limits
rate_limits:
  global: 60/minute         # all tools combined
  per_tool:
    filesystem_write_file: 10/minute
    "mcp_proxy.*": 30/minute  # glob pattern — all matched tools share one counter

# Optional: argument-value filtering
argument_filters:
  - name: no-credentials
    pattern: '(?i)(password|secret|token)\s*[:=]\s*\S+'
    fields: [path, query, body]
    action: block
    decode: [base64, urlsafe_base64, url]

# Optional: human-in-the-loop approval (requires state_backend.type: dragonfly)
hitl:
  approval_required: ["filesystem_delete_*", "sqlite_execute"]
  shadow: ["mcp_proxy.*"]   # shadow mode: log only, return synthetic empty success
  timeout_seconds: 300
  notify:
    type: ntfy
    topic: homelab-hitl
```

The `mode` field controls which tools register:
- `mode: read` — read-decorated tools only (e.g. `filesystem_read_file`, `filesystem_list_dir`)
- `mode: write` — both read and write tools
- Notification modules are write-only by design — no `mode` field needed
- **`mcp_proxy` ignores `mode` entirely** — use `tool_allowlist`/`tool_denylist` in config instead (v0.4.0+)

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

# With Dragonfly/Valkey/Redis state backend (required for multi-process rate limiting and HITL)
pip install "scoped-mcp[dragonfly]"

# With HashiCorp Vault credential source
pip install "scoped-mcp[vault]"

# With OpenTelemetry tracing
pip install "scoped-mcp[otel]"

# Everything
pip install "scoped-mcp[all]"
```

### CLI

```bash
# Start a proxy server (explicit subcommand)
scoped-mcp run --manifest manifests/research-agent.yml

# Validate a manifest file (suitable for CI pre-flight)
scoped-mcp validate --manifest manifests/research-agent.yml

# HITL approval management (requires Dragonfly)
scoped-mcp hitl list
scoped-mcp hitl approve <approval-id>
scoped-mcp hitl reject <approval-id> [reason]
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

  # stdio example — subprocess started once at module startup, reused for all tool calls
  some-local-tool:
    type: mcp_proxy
    config:
      command: /usr/local/bin/python3
      args: [/path/to/server.py]
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

**Stdio transport** opens a persistent subprocess at server startup (via `startup()` lifecycle hook) and reuses it for all tool calls. The subprocess is cleanly shut down when the server stops. HTTP transport reconnects per-call.

**Schema validation (v0.9+):** every proxied `tools/call` is validated against the upstream tool's JSON Schema before forwarding. Schemas are cached at discovery and refreshed on stdio reconnect. The refresh path merges into the existing cache — tools that disappear from a refresh keep their cached schema (fail-safe: stale-but-strict over no validation). Validation failures log argument keys only, never values.

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

Emits to stdout and/or a log file. All entries include timing — useful for spotting slow backends or runaway tool loops. Sensitive keys (`_TOKEN`, `_PASSWORD`, `_SECRET`, `_KEY`, credential fields from Vault) are redacted before the entry is written.

## Middleware

Middleware intercepts every tool call after scoping is applied and before the handler executes. Pass a list of middleware instances to `build_server()`:

```python
from scoped_mcp.contrib.otel import OtelMiddleware
from scoped_mcp.contrib.rate_limit import RateLimitMiddleware

server = build_server(agent_ctx, manifest, middleware=[OtelMiddleware()])
```

Middleware runs in list order; each receives `agent_ctx`, `tool_name`, `kwargs` (a copy — mutations don't propagate), and `call_next`. Call `await call_next()` exactly once to continue the chain.

Middleware from the `rate_limits:` and `argument_filters:` manifest sections is registered automatically — no `build_server()` call needed for those.

### OpenTelemetry

`OtelMiddleware` emits one OTel span per tool call with `scoped_mcp.*` attributes (`agent.id`, `agent.type`, `tool.name`, `call.status`). Tool arguments are excluded from spans to prevent credential leakage. Exception messages are redacted before reaching the OTLP collector.

**Auto-enable via environment variable** — no code changes needed:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo-host:4317
export OTEL_SERVICE_NAME=scoped-mcp
pip install "scoped-mcp[otel]"
```

Compatible with SigNoz, Grafana Tempo, Jaeger, and Langfuse OTLP ingest. If `OTEL_EXPORTER_OTLP_ENDPOINT` is set but `[otel]` is not installed, the server starts normally — the dependency is silently skipped.

## Hardening (v0.7–v1.0)

Four optional guardrails added in the v0.7 → v1.0 roadmap. Each is independently enabled via manifest sections; none affect the base proxy behaviour when omitted.

### Rate Limiting

`RateLimitMiddleware` (v0.7.0) enforces sliding-window limits per agent. Configured via `rate_limits:` in the manifest; auto-registered at startup.

```yaml
state_backend:
  type: dragonfly          # required for multi-process; in_process works for single-agent
  url: redis://127.0.0.1:6379/0

rate_limits:
  global: 60/minute        # all tools combined, scoped to this agent
  per_tool:
    filesystem_write_file: 10/minute
    "mcp_proxy.*": 30/minute   # glob: all matched tools share one counter
```

**State backend selection:**
- `type: in_process` (default) — asyncio-based sliding window, no external deps. Resets on server restart. Use for single-agent or development setups.
- `type: dragonfly` — Lua sorted-set sliding window in Dragonfly/Valkey/Redis. Persists across restarts, works across multiple proxy processes sharing the same agent identity. Requires `pip install "scoped-mcp[dragonfly]"`.

The homelab personal-agent manifest uses `type: dragonfly` pointing at a Dragonfly instance running on claudebox (`~/docker/scoped-mcp-cache/`).

**Fail-closed policy:** backend errors (Dragonfly unreachable) block tool calls rather than silently bypassing limits. This is explicit and tested.

### Vault Credentials

`VaultCredentialSource` (v0.8.0) fetches agent credentials from HashiCorp Vault using AppRole auth. Requires `pip install "scoped-mcp[vault]"`.

```yaml
credentials:
  source: vault
  vault:
    addr: http://vault.internal:8200
    auth: approle
    role_id_env: VAULT_ROLE_ID
    secret_id_env: VAULT_SECRET_ID
    path: "secret/agents/{agent_type}"   # {agent_type} interpolated at startup
    kv_version: 2                         # or 1
```

The bundle is fetched once during `build_server()` and filtered per module — each module receives only the credential keys it declares. The `secret_id` is cleared from memory before the AppRole login call. A background renewal task refreshes the client token at 2/3 of the lease TTL; `close()` bounds the wait to 5 seconds.

See `examples/vault/` in the repo for a working manifest, Vault policy HCL, and AppRole setup script.

**Note:** no Vault server is deployed in the homelab at this time. This is a client-side capability — the proxy can consume Vault-backed secrets when pointed at an existing Vault instance.

### Argument Filters

`ArgumentFilterMiddleware` (v0.9.0) pattern-matches against tool argument values before the call is forwarded. Configured via `argument_filters:` in the manifest; auto-registered after rate limiting.

```yaml
argument_filters:
  - name: no-credentials
    pattern: '(?i)(password|secret|token)\s*[:=]\s*\S+'
    fields: [path, query, body]
    action: block
    decode: [base64, urlsafe_base64, url]   # decode steps to catch obfuscated payloads
    case_insensitive: true

  - name: no-path-traversal
    pattern: '\.\.[/\\]'
    fields: [path, filename]
    action: block
```

**Decode steps:** each step decodes the raw value and adds the result to the candidate set. Available steps: `base64`, `urlsafe_base64`, `url`. Decoded candidates are capped at 64 KiB each. Chain steps to catch layered encoding: `[base64, url]`.

**Action types:**
- `block` — raise `ConfigError`, tool call rejected. The agent-facing message is generic (rule/field detail stays in the audit log so the agent cannot enumerate filter configuration via probe-and-observe).
- `warn` — log `argument_filter_warned` and continue.

**Block before warn:** block rules are evaluated first and short-circuit on the first hit.

**Threat-model caveats** (documented in `docs/threat-model.md`):
- Only top-level string fields are inspected — nested dicts/lists are not walked
- Pattern operators trust the manifest author (ReDoS is the operator's responsibility; 64 KiB input cap bounds amplification)
- Schema validation (`mcp_proxy`) catches shape/type errors; argument filtering catches value-level patterns — use both for defence-in-depth

### HITL Approval

`HitlMiddleware` (v1.0.0) gates selected tool calls on explicit operator approval before forwarding. Requires `state_backend.type: dragonfly` (manifest validator enforces this).

```yaml
state_backend:
  type: dragonfly
  url: redis://127.0.0.1:6379/0

hitl:
  approval_required: ["filesystem_delete_*", "sqlite_execute"]
  shadow: ["mcp_proxy.*"]    # shadow mode: log-only, return synthetic empty success
  timeout_seconds: 300       # auto-reject after this many seconds
  notify:
    type: ntfy               # or: log (default), webhook, matrix
    topic: homelab-hitl
```

**Shadow mode** takes precedence over `approval_required`. A tool matched by both `shadow` and `approval_required` returns a synthetic empty-success response without forwarding upstream — regardless of operator decision. Use for silent dry-run observation of high-risk tool patterns.

**Notifiers:** `LogNotifier` (default, no deps), `NtfyNotifier`, `WebhookNotifier`, `MatrixNotifier`. Transport failures are logged and swallowed — a notification outage cannot wedge the approval loop. Notifiers receive only a sanitised argument summary; raw values never reach the operator channel.

**Fail-closed:** backend write failures produce `HitlRejectedError`, not a forwarded call.

**Operator CLI:**
```bash
scoped-mcp hitl list                    # show pending approvals
scoped-mcp hitl approve <approval-id>   # approve and unblock the agent
scoped-mcp hitl reject <id> "reason"    # reject; agent gets HitlRejectedError
```

Approval IDs have the format `{agent_id}.{12-hex-chars}` (48 bits entropy). The agent-id prefix lets the CLI find the right Dragonfly key without a separate lookup.

**Publish-before-subscribe safety:** `StateBackend.subscribe()` is a coroutine that performs channel registration synchronously when awaited — the middleware subscribes before sending the notification, eliminating the race where a fast operator approval would be dropped.

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
