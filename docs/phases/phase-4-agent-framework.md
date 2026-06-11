# Phase 4 — Agent Framework

**Completed:** 2026-04-02  
**Snapshots:** pre-Phase-4 ID 269, post-Phase-4 ID 270  
**Smoke tests:** 30/30 passed

## What Was Built

Phase 4 established the agent runtime layer on forge — everything needed to launch Claude Code agents with resource isolation, per-identity NATS credentials, and a structured manifest contract.

## Components Deployed

### Runtime Tooling
- **Claude Code CLI** — installed and configured under the `ted` user
- **Node.js v22** — required by Claude Code; installed via NodeSource

### Directory Structure
```
~/.helm/
├── bin/
│   └── helm-launch          # agent launch script
├── manifests/
│   ├── SCHEMA.md            # manifest schema v1
│   ├── helm-build.yaml      # helm-build agent manifest
│   ├── platform.yaml        # platform agent manifest
│   └── temporal-worker.yaml # temporal-worker agent manifest
└── credentials/
    └── nats-users.env       # per-user NATS passwords (600)

~/.claude/
├── projects/                # per-agent project dirs (CLAUDE.md, memory)
│   ├── helm-build/
│   ├── platform/
│   └── temporal-worker/
└── memory/
    └── shared/              # 75 shared memory files bootstrapped
```

### Agent Manifest Schema v1

Each agent type has a manifest at `~/.helm/manifests/<agent-type>.yaml` declaring:
- **Resources** — cgroup tier (`resident` / `burst` / `default`) and optional hints
- **NATS** — assigned user and subject permissions
- **Filesystem** — read/write paths (informational in v1; enforced in Phase 5 with Landlock)
- **External API** — allowed hosts and methods (informational in v1; enforced in Phase 5 with HTTP proxy)
- **Team** — system team membership (`watch` / `engineers` / `archivists` / `purser` / `null`)

Three manifests deployed: `helm-build` (burst tier), `platform` (resident tier), `temporal-worker` (default tier).

See [SCHEMA.md](../../.helm/manifests/SCHEMA.md) for full field reference.

### cgroup v2 Resource Pools

Three user-level systemd slices under `~/.config/systemd/user/`:

| Slice | CPUWeight | MemoryMax | MemoryHigh | Use |
|-------|-----------|-----------|------------|-----|
| `helm-resident.slice` | 400 | 16 GB | 14 GB | Always-on platform agents |
| `helm-burst.slice` | 200 | 8 GB | 6 GB | Build agents, active work |
| `helm-default.slice` | 100 | — | — | Background / light agents |

Slices are user-scoped (`--user` systemd units) — no root required. `helm-launch` selects the slice from the manifest's `tier` field via `systemd-run --user --slice=`.

### NATS Per-User Auth

NATS migrated from single shared token to per-user authorization block in `nats.conf`. Three users with subject-level ACLs:

| User | Publish | Subscribe |
|------|---------|-----------|
| `platform` | `>` (full) | `>` (full) |
| `helm-build` | `tasks.helm-build.>`, `events.helm-build.>` | `tasks.helm-build.>`, `_INBOX.>` |
| `temporal-worker` | `tasks.temporal.>`, `events.temporal.>` | `tasks.>`, `_INBOX.>` |

See [nats.md](../components/agent/nats.md) for full configuration.

### helm-launch v1

`~/.helm/bin/helm-launch` — the agent launch entrypoint. Reads a manifest, resolves the cgroup slice, injects NATS credentials and API key, and launches Claude Code under `systemd-run`. Supports `--dry-run` for inspection without execution.

See [helm-launch.md](../../design/helm-launch.md) for usage and internals.

### NATS CLI

`/usr/local/bin/nats` v0.3.2 — installed directly on the host. Required because the NATS container uses a distroless image (no shell), so CLI tooling must live on the host. Used for stream inspection, subject testing, and credential validation.

### Shared Memory Bootstrap

75 shared memory files copied from claudebox to `~/.claude/memory/shared/` on forge — giving agents immediate access to project context, infrastructure docs, and prior decisions without waiting for memory-sync to populate from scratch.

## Smoke Tests (30/30)

- Claude Code launches under each cgroup slice
- helm-launch resolves tier correctly for all three manifests
- `--dry-run` outputs correct slice and NATS user per manifest
- NATS auth accepted for all three users
- Subject ACLs enforced (publish/subscribe outside permissions rejected)
- NATS CLI connects and can inspect streams
- Shared memory files accessible from agent project dirs
- systemd slice units active and reporting resource accounting

## Phase 5 Preview

Phase 5 will harden the informational constraints from Phase 4:
- **Landlock** — enforce filesystem read/write permissions from manifests at the kernel level
- **HTTP proxy** — enforce external API allowlist from manifests
- **Agent workspace markers** — AGENT_WORKSPACE.md protocol ported from claudebox

---

*Previous phase: Phase 3 — Auth (Authentik SSO, SWAG forward auth, Grafana OIDC)*
