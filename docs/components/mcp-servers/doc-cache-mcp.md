# doc-cache-mcp

Capability-scoped FastMCP server for the forge documentation cache. Exposes exactly three
verbs — **list**, **add**, **sync** — over the shared docs cache (`~/docs/doc-sync.yml`),
validating every source URL against an allowlist before it can enter the cache.

It replaced the research agent's generic `system-ops`/`homelab-ops-mcp` doc-sync exemption
(ADR-0005) with a purpose-built tool (ADR-0006, `doc-cache-mcp` build, 2026-07-07). After
cutover, research holds no generic file/command primitive at all.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `doc-cache-mcp` |
| Type | always-on |
| Script | `/opt/venvs/doc-cache-mcp/bin/doc-cache-mcp` |
| Interpreter | none |
| Port | `127.0.0.1:8503` (streamable-http, loopback only by design) |
| Repo | `~/repos/personal/doc-cache-mcp/` ([TadMSTR/doc-cache-mcp](https://github.com/TadMSTR/doc-cache-mcp) on GitHub) |

## Why capability-scoped

The old model gave research broad primitives (`read_file`/`edit_file`/`run_command`) fenced
by deny-list argument filters — a path filter constrained *where* an edit landed but not
**what URL** it pointed doc-sync.yml at, leaving a live cache-poisoning/SSRF-shaped gap.
`doc-cache-mcp` flips this to a narrow, typed surface with URL validation as a first-class
control.

## Tools

| Tool | Behaviour |
|------|-----------|
| `doc_cache_list_services` | Read-only. Lists each configured service, its topics/URLs, chunk counts, and last-synced date. |
| `doc_cache_add_service` | Registers a service + `[{topic, url}]`. Validates every URL against the allowlist, then does a structural YAML merge (dedup by topic), atomic write, and single-file git commit. Never fetches. |
| `doc_cache_sync` | Ingests/refreshes a configured service: fetch → convert → chunk → cache → index into memsearch. Service must already exist in config. Rate-limited to 10/minute in the research manifest (LLM/embedding cost control). Result gained a top-level `ok`/`index_error` pair in v0.2.0 — check those rather than inferring success from the absence of `errors`. |

## Source-URL allowlist (the security core)

Every URL passed to `doc_cache_add_service` is checked before anything is written:

- Scheme must be `https`; IP-literal hosts are rejected (name-based allowlist only).
- Public hosts must be on the allowlist **and** every address they currently resolve to
  must be public (defeats DNS-rebind bypass).
- Forge endpoints (exact host + path prefix) are explicitly trusted individually and may
  resolve to private forge addresses.
- Default-deny — anything else is refused; a missing allowlist file denies everything.

Allowlist file: `host-forge-scripts/doc-cache-allowlist.yml` (git-backed, sysadmin-editable,
re-read on every call — edits take effect without a restart).

## Architecture

Does not re-implement chunking or shell out — imports the shared `doc-sync.py`
(`sync_service()`) as the single source of truth for fetch/convert/chunk/write. The CLI
(`doc-sync.py --service …`, the `doc-sync-daily` cron — see
[doc-sync-daily.md](../platform/doc-sync-daily.md)) and the MCP share the same core logic
and the same `flock` on the state file, so they never race writes. Its only write surface is
`doc-sync.yml` (structural merge + atomic write + single-file git commit) and the docs cache
directory.

## Configuration

Environment variables (prefix `DOC_CACHE_MCP_`):

| Var | Default | Meaning |
|-----|---------|---------|
| `DOC_CACHE_MCP_TRANSPORT` | `http` | `http` (streamable-http) or `stdio` |
| `DOC_CACHE_MCP_HOST` | `127.0.0.1` | Bind host — loopback only by design |
| `DOC_CACHE_MCP_PORT` | `8503` | Bind port |
| `DOC_CACHE_MCP_DOCSYNC_PATH` | `~/scripts/doc-sync.py` | Shared doc-sync logic to import |
| `DOC_CACHE_MCP_CONFIG_PATH` | `~/docs/doc-sync.yml` | Docs cache config the add-tool edits |
| `DOC_CACHE_MCP_ALLOWLIST_PATH` | `host-forge-scripts/doc-cache-allowlist.yml` | Source-URL allowlist |
| `DOC_CACHE_MCP_GIT_COMMIT` | `true` | Commit `doc-sync.yml` after a successful add |
| `DOC_CACHE_MCP_MAX_ENTRIES_PER_ADD` | `50` | Ceiling on source entries accepted in one `add_service` call |
| `DOC_CACHE_MCP_GIT_PUSH` | `false` | Push the `doc-sync.yml` commit after a successful add. **Off by default** — turning it on gives this MCP unattended write access to a shared repo's `main`, gated by seven fail-closed guards (identity, scoped deploy key, commit-range ownership, path scope, additive-only diff, audit log, review-branch fallback on any trip). See the [repo README](https://github.com/TadMSTR/doc-cache-mcp#pushing) for the full guard list. |
| `DOC_CACHE_MCP_DEPLOY_KEY_PATH` | unset | ed25519 ssh key used for the push, required when `GIT_PUSH` is on. New credential: `~/.secrets/doc-cache-mcp-deploy`, mode `0600`, scoped to write on `host-forge/scripts` only. |
| `DOC_CACHE_MCP_PUSH_REMOTE` / `_PUSH_BRANCH` | `origin` / `main` | Push target |
| `DOC_CACHE_MCP_REVIEW_BRANCH_PREFIX` | `doc-cache-mcp/review` | Where a guarded-off commit lands instead of `main` |
| `DOC_CACHE_MCP_COMMIT_IDENTITY_NAME` / `_EMAIL` | `doc-cache-mcp` / `doc-cache-mcp@forge` | Git identity used for tool commits |
| `DOC_CACHE_MCP_AUDIT_LOG_DIR` | unset | Append-only JSONL sink for push decisions. Unset = no audit events. |

> v0.2.0 (this deployment surface) is **not yet live** — it needs one `pm2 restart doc-cache-mcp` to pick up the doc-sync module change.

Optional telemetry: `OTEL_EXPORTER_OTLP_ENDPOINT` (OTLP span export, `service.name` is
`doc-cache-mcp`) and `INFLUXDB_URL`/`INFLUXDB_TOKEN`/`INFLUXDB_BUCKET` (best-effort per-call
metrics, default bucket `doc-cache-mcp`) — each gated on its own env var with no import cost
when unset.

## Dependencies

- `~/scripts/doc-sync.py` — shared fetch/convert/chunk logic
- `~/docs/doc-sync.yml` — docs cache config (git-backed)
- `host-forge-scripts/doc-cache-allowlist.yml` — source-URL allowlist
- memsearch — sync indexes fetched content there

## scoped-mcp Access

Registered in `research-agent.yml` only, with a 3-tool allowlist
(`doc_cache_list_services`, `doc_cache_add_service`, `doc_cache_sync`) and a 10/minute rate
limit on `doc_cache_sync`. This supersedes research's former `system-ops`/`homelab-ops-mcp`
grant entirely — no other agent currently has access.

## Operations

```bash
# Status
pm2 show doc-cache-mcp

# Logs
pm2 logs doc-cache-mcp --lines 50

# Restart
pm2 restart doc-cache-mcp

# Manual health check
curl -s http://127.0.0.1:8503/health
```

## Related docs

- [doc-sync-daily.md](../platform/doc-sync-daily.md) — the cron that shares this server's core sync logic
- `host-forge/services.md` — port registry entry
