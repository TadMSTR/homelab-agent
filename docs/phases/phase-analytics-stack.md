# Phase: Analytics Stack

**Completed:** 2026-04-15
**Build plan:** `~/.claude/comms/artifacts/build-plans/forge-analytics-stack/`
**Security audit:** `/home/ted/repos/audits/security-audits/2026-04-15-forge-analytics-stack.md`

## What Was Built

The analytics stack adds LLM observability (Langfuse) and distributed APM (SigNoz) to forge, along with the backup infrastructure to protect their data. Phase 3 (additional research-layer services) was deferred pending dedicated build plans.

## Phases

### Phase 0 — NATS Verification

Confirmed existing NATS multi-user configuration (Phases 4/5) intact after recent rotation cron run. No compose changes needed. NATS restart performed to verify clean state — all subjects and user permissions nominal.

### Phase 1 — Langfuse

Deployed Langfuse v3.167.4 as a 6-container stack on an isolated `langfuse-internal` network.

**Key deployment discoveries:**

- **MinIO is mandatory** as of ~v3.140+. The `langfuse-worker` and `langfuse-web` containers check for a healthy S3 endpoint at startup and refuse to start without it. The bucket (`langfuse`) is auto-created by the MinIO entrypoint command.

- **ClickHouse migration URL must use `clickhouse://` (TCP 9000)**, not `http://`. Using the HTTP scheme causes migration failures — the migration client requires the native protocol.

- **Dragonfly thread/memory constraint**: forge-wide pattern — Dragonfly requires ≥256MB maxmemory per proactor thread. At 512MB (Langfuse's cache budget), maximum safe `--proactor_threads` is 2.

- **Dragonfly password env var**: Dragonfly exposes all CLI flags as `DFLY_<flagname>` environment variables. Setting `DFLY_requirepass` avoids the `--requirepass` CLI arg approach, which embeds the plaintext password in `docker inspect Args` output.

- **Authentik SSO wiring** required three non-obvious settings:
  - `HOSTNAME=0.0.0.0` (Langfuse binds on all interfaces so SWAG can reach it via forge-net)
  - `AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING=true` (Langfuse-specific var; the `DANGEROUS` variant doesn't apply here)
  - No trailing slash on `AUTH_CUSTOM_ISSUER` (trailing slash → double-slash URL → nginx 301 → OIDC failure)
  - `extra_hosts: auth.helmforge.me:172.20.1.5` for server-side OIDC discovery through SWAG

First-login flow: admin account creation → `Helm` organization → `helm-default` project → Authentik SSO linked.

### Phase 2 — SigNoz + Alloy OTLP

Deployed SigNoz v0.118.0 and configured Alloy on claudebox to forward telemetry.

**Key deployment discoveries:**

- **`cluster.xml` ZooKeeper hostname mismatch**: SigNoz's shipped `cluster.xml` uses `zookeeper-1` as the hostname, but the compose container is named `signoz-zookeeper`. ClickHouse was unable to connect to ZooKeeper and all replica-table operations failed. Fix: edit `cluster.xml` before first deploy.

- **Config files must come from the matching release tag**: `config.xml`, `users.xml`, `cluster.xml`, `custom-function.xml`, `otel-collector-config.yaml`, and `otel-collector-opamp-config.yaml` were pulled from the SigNoz GitHub repo at `v0.118.0`. Do not use files from `main` for a pinned deploy.

- **`histogramQuantile` binary staged manually**: The one-shot `signoz-init-clickhouse` container downloads this binary from GitHub releases at first deploy. Binary was staged and existence guard added per M2 security finding (no upstream checksum available).

- **OTLP ports intentionally LAN-open**: `4317:4317` and `4318:4318` are bound on `0.0.0.0` to allow claudebox → forge telemetry forwarding over the LAN. Pre-approved in build plan.

- **Alloy config requires root**: On claudebox, Alloy's systemd unit runs as root. The OTLP exporter config targets `<server-ip>:4317` (forge). Works cleanly with root; would need capability grants if user is changed.

SigNoz SSO note: SigNoz only supports Google Workspace SSO for enterprise auth. Authentik is not compatible. Native admin account is the auth gate on forge — no Authelia layer applied (deferred, M1 from security audit).

### Phase 3 — Deferred

The following services were scoped for this build plan but deferred pending dedicated research agent build plans:
- Temporal (workflow engine)
- Milvus (vector database)
- n8n (workflow automation)
- Plane (project management)
- task-queue-mcp (MCP server for agent task queue)

## Security Audit Summary

Audit performed 2026-04-15 after Phase 2. Scope: Langfuse stack, SigNoz stack, Alloy OTLP exporter, SWAG proxy confs.

**Result:** 0 critical, 0 high, 2 medium, 6 low.

| Finding | Status |
|---------|--------|
| M1 — No Authelia/SSO layer on SWAG confs | Partial — Langfuse: Authentik SSO wired. SigNoz: deferred (incompatible SSO options). |
| M2 — signoz-init-clickhouse binary unverified download | ✓ Fixed — pre-staged + existence guard |
| L1 — Dragonfly password in docker inspect | ✓ Fixed — moved to `DFLY_requirepass` env var |
| L2 — pprof reachable from forge-net | ✓ Fixed — `localhost:1777` |
| L3 — Config files world-readable | ✓ Fixed — XML: 640, YAML: 644 |
| L4 — Langfuse Authentik SSO not wired | ✓ Fixed — Authentik OIDC provider `lang-fuse` wired |
| L5 — Retention not configured | ✓ Fixed — ClickHouse TTLs (Langfuse) + UI retention (SigNoz) |
| L6 — Volumes not backed up | ✓ Fixed — `~/scripts/docker-stack-backup.sh` on forge, 2 AM daily |

## Forge Backup Script

`/home/ted/scripts/docker-stack-backup.sh` was created as part of this phase (L6 fix). It's a fork of the claudebox `docker-stack-backup.sh` pattern: stop stack → `sudo tar` compose + appdata → restart.

- Covers all 9 appdata stacks on forge
- Destination: `/mnt/atlas/forge/backups/docker-backups/`
- Cron: `0 2 * * *` as `ted` via `/etc/cron.d/docker-stack-backup`
- Offset from claudebox (1 AM) to avoid NFS write collision

## Component Docs

- [langfuse.md](../components/langfuse.md)
- [signoz.md](../components/signoz.md)
