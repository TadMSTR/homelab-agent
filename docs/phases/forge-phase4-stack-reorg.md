# Forge Phase 4 — Stack Reorganization

**Completed:** 2026-05-12
**Snapshots:** pre-phase4-observability, pre-phase4-graphiti, pre-phase4-agent-platform (all in `/.snapshots/`)

## What Was Built

Housekeeping reorganization of forge Docker stacks to match the `~/docker/<stack>/` + `/opt/appdata/<stack>/<service>/` directory convention. Dragonfly and NATS consolidated into a new `agent-platform` stack (NATS brought up for the first time). graphiti-mcp added to forge-net (omission from original deploy). `stack-inventory.md` committed to `host-forge/knowledge-base` as the ongoing reference for what runs on forge.

No new user-facing services; this phase establishes the structural baseline that subsequent phases build on.

## Appdata Migration

Before this phase, several services sat at the `/opt/appdata/` root rather than under a stack subdirectory. Migrated to match convention:

| Service | Before | After |
|---------|--------|-------|
| `grafana` | `/opt/appdata/grafana/` | `/opt/appdata/observability/grafana/` |
| `influxdb` | `/opt/appdata/influxdb/` | `/opt/appdata/observability/influxdb/` |
| `loki` | `/opt/appdata/loki/` | `/opt/appdata/observability/loki/` |
| `neo4j` | `/opt/appdata/neo4j/` | `/opt/appdata/graphiti/neo4j/` |

Standalone `dragonfly` and `nats` stack directories retired; replaced by `agent-platform` stack.

See [appdata-layout.md](../operations/appdata-layout.md) for the full convention.

## agent-platform Stack

New stack combining Dragonfly and NATS, replacing the previous standalone `dragonfly` and `nats` stack directories.

| Service | Purpose |
|---------|---------|
| Dragonfly | Platform-internal cache (scoped-mcp state, agent-bus session cache, gateway session mapping) |
| NATS v2.12.6 | Agent messaging bus — first time brought up on forge; compose and config existed from Phase 3 NATS setup |

7 NATS service users were provisioned as part of this phase. `docker-stack-backup.sh` needed no update — it uses auto-discovery and picks up `agent-platform` automatically, dropping the retired standalone stacks.

## graphiti-mcp forge-net Fix

graphiti-mcp was missing its `forge-net` attachment from the original deploy. Any service attempting to reach graphiti via the forge-net bridge was silently failing. Added `forge-net: external: true` to the graphiti-mcp compose config and restarted the service.

This was a latent bug; no traffic had yet depended on that path, but Phase 5 and 6 services would have failed when they attempted to reach it.

## stack-inventory.md

`stacks/stack-inventory.md` committed to `host-forge/knowledge-base` (commit `18403f9`) as the authoritative, ongoing reference for what stacks run on forge. `services.md` in the same repo lists planned vs running stacks at the phase-2 snapshot — update `services.md` as new stacks go live to keep it consistent with `stack-inventory.md`.

## Next Phase

**Phase 5 — First User Stack:** Dragonfly, scoped-mcp, and `claude -p` runner container for Ted's gateway user stack. Mounts `users/ted-gateway-config` from atlas Gitea.
