# Phase 7 — Agent Infrastructure

**Completed:** 2026-04-03

Phase 7 added the operational infrastructure layer beneath the agent execution model: a pre-warmed ephemeral clone pool (btrfs CoW), a hot memory cache (Dragonfly), an A→B task routing layer with transit logging, and an agent registry providing live observability across all 7 agents.

## What Was Built

### btrfs CoW Ephemeral Pool

Golden masters at `/opt/helm/agents/<type>/` are now btrfs subvolumes. The pool manager pre-warms a configurable number of snapshot clones per agent type, so headless launches can claim an already-copied session directory instead of waiting for a fresh `btrfs subvolume snapshot`.

**Pool targets (by tier):**
- `resident` → 2 warm clones
- `burst` → 1 warm clone
- `default` → 0 (clone on demand)

`create-ephemeral-clone.sh` was updated to check the pool first (atomic `.warm` marker claim via `rm`), falling back to a fresh btrfs snapshot if the pool is empty. Symlink fallback is preserved for non-btrfs golden masters.

PM2: `helm-pool-manager` (every minute). Pool state written atomically to `~/.helm/pool-state.json`.

### Dragonfly Hot Memory

Redis-compatible in-memory store for agent hot state — cross-invocation working memory that doesn't need to survive restarts.

| Setting | Value |
|---------|-------|
| Image | `docker.dragonflydb.io/dragonflydb/dragonfly:v1.37.2` (pinned) |
| Port | `127.0.0.1:6380` (localhost-only) |
| Max memory | 2 GB |
| Threads | 4 (`--proactor_threads=4` — 256 MB minimum per thread) |
| Data dir | `/opt/appdata/dragonfly` |
| Auth | `--requirepass` (password in `~/docker/dragonfly/.env` + `~/.helm/dragonfly.env`) |
| Network | `forge-net` only |
| Backup | Not backed up — hot cache, rebuildable on restart |

`agent-memory-hot.sh` wrapper provides `get`, `set`, and `keys` operations with automatic key prefixing (`helm:agent:<type>:<key>`) and a 1-hour default TTL. Password injected via `DRAGONFLY_PASSWORD` env var (loaded from `~/.helm/dragonfly.env` via helm-launch `EnvironmentFile`).

**Security fix applied (H-02):** Dragonfly was initially deployed without auth on `forge-net`. `--requirepass` added during Phase 7 security audit; password stored in `~/docker/dragonfly/.env` (600) and `~/.helm/dragonfly.env` (644).

### A→B Agent Routing

`route-task.sh` provides a structured task routing layer: read a task YAML, validate the target, launch the agent headless, and log the transit.

**Task YAML schema:**
```yaml
id: <uuid>
trace_id: <uuid>          # optional, defaults to id
source_agent: <name>
target_agent: <name>
summary: <one-line>
payload:
  description: <task description passed to claude -p>
status: pending           # updated to completed/failed on exit
```

Security: YAML is parsed via Python with `sys.argv[1]` (not string interpolation). `TARGET` validated against `^[a-zA-Z0-9_-]+$` before any path construction or execution. Transit log entries written via env vars, not embedded YAML values.

**Transit log:** `~/.helm/logs/transit.jsonl` (append-only JSONL)

```json
{
  "timestamp": "2026-04-03T21:00:00Z",
  "trace_id":  "<uuid>",
  "task_id":   "<uuid>",
  "source":    "platform",
  "target":    "security",
  "status":    "success",
  "exit_code": 0,
  "duration_ms": 4200
}
```

`transit-query.sh` provides `recent [N]`, `trace <id>`, `agent <name>`, and `failures` subcommands.

**Log rotation:** `rotate-transit-log.sh` (PM2: `transit-log-rotate`, 1st of month 04:00) archives entries older than 90 days to `~/.helm/logs/transit-archive/YYYY-MM.jsonl`.

### Agent Registry

`registry-update.sh` rebuilds `~/.helm/registry.yaml` from manifests + PM2 runtime state + pool state. PM2: `helm-registry-refresh` (every 5 minutes).

**7 agents currently registered:** docs, helm-build, platform-health, platform, security, temporal-worker, update.

`registry-query.sh` provides `list`, `show <name>`, `team <name>`, and `tier <tier>` subcommands.

**Schema additions (SCHEMA.md v1.1):**
- `isolation` block expanded (unix_user, apparmor_profile, seccomp, capabilities_drop)
- `internal_api` field for declaring internal TCP endpoints
- `type` field (`system` / `user`)
- `schema_version` field

Team field normalization: some manifests had `team` as a dict with `peers`/`escalate_to` keys. Registry update normalizes to string (or null).

## PM2 Services Added

| ID | Name | Schedule | Description |
|----|------|----------|-------------|
| 6 | `helm-pool-manager` | `* * * * *` | Replenish pre-warmed clone pool per agent type |
| 7 | `transit-log-rotate` | `0 4 1 * *` | Archive transit log entries >90 days |
| 8 | `helm-registry-refresh` | `*/5 * * * *` | Rebuild agent registry from manifests + runtime |

## Security Audit

7 findings (0 critical, 2 high, 2 medium, 3 low). All resolved same session:

- **H-01:** `route-task.sh` Python `-c` injection — rewritten with env vars + heredocs, YAML parsed via `sys.argv[1]`
- **H-02:** Dragonfly unauthenticated on `forge-net` — `--requirepass` added, password in `.env` files
- **M-01:** `TARGET` validation in `route-task.sh` — `^[a-zA-Z0-9_-]+$` guard added
- **M-02:** UUID extraction in `pool-manager.sh` — exact UUID regex in sed and Python
- **L-01:** Atomic writes for `registry.yaml` and `pool-state.json` — `.tmp` + `os.replace()`
- **L-02:** `transit-query.sh` `grep -F` + agent name validation
- **L-03:** Dragonfly image pinned to `v1.37.2`

Full report: `~/repos/audits/security-audits/helm-phase7-agent-infrastructure/report.md`

## Related Docs

- [dragonfly.md](../components/agent/dragonfly.md) — hot memory stack
- [pool-manager.md](../components/agent/pool-manager.md) — btrfs clone pool
- [agent-routing.md](../../design/agent-routing.md) — task routing and transit log
- [agent-registry.md](../../design/agent-registry.md) — agent registry and observability
- [helm-launch.md](../../design/helm-launch.md) — ephemeral clone integration
- [phase-6-system-agents.md](phase-6-system-agents.md) — Phase 6 context
