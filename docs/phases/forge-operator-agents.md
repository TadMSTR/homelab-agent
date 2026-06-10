# Forge — Operator Agents Build

**Completed:** 2026-05-16
**Snapshots:** pre-phase-operator-agents (in `/.snapshots/`)

## What Was Built

Five-phase build (A–E) deploying the operator agent infrastructure on forge: Dockhand stack, Hister (bookmarks), CloudCLI, memory stack (Milvus + OpenSearch), and Langfuse observability wiring. All five phases completed in this session. Agents now have a monitored, key-isolated Langfuse project (`forge-agents`) with per-agent `.env` files sourcing keys from `/opt/secrets/langfuse.env`.

## Components Deployed

| Stack/Service | Purpose | Notes |
|--------------|---------|-------|
| Dockhand | Docker fleet oversight, update notifications | /opt/appdata/dockhand; runs as uid=1000 |
| Hister | Bookmark manager for forge operators | Authentik forward-auth on SWAG |
| CloudCLI | CLI tool web UI | SWAG-proxied, storage network blocked |
| memory-stack | Milvus (vector) + OpenSearch (full-text) | Agent search infrastructure |
| Langfuse `forge-agents` project | LLM observability per agent | Keys isolated in /opt/secrets/langfuse.env |

## Authentik Integration

All three user-facing services (Dockhand, Hister, CloudCLI) wired to Authentik forward auth in SWAG. Subdomain proxy confs written; authentication flow active.

## Langfuse Wiring (Phase E)

LANGFUSE_INIT_* env vars do not auto-propagate from `.env` file to the running container — docker compose restart does not re-read `.env` for variable substitution purposes. Project seeded directly via Postgres INSERT into the `langfuse` database:
- Organization: `helm-default` (existing)
- Project: `forge-agents-proj-001`
- Public key: `pk-lf-<redacted>` (stored in /opt/secrets/langfuse.env)
- Secret key SHA256-hashed and stored in `api_keys` table

Agent `.env` files written by `/home/ted/scripts/write-agent-envs.sh`, sourcing from `/opt/secrets/langfuse.env` (chmod 600). One file per agent in `/opt/agents/<agent>/.env`.

## Security Audit Results

Security audit returned 8 findings (1 High, 4 Medium, 3 Low). All resolved:

| ID | Severity | Finding | Resolution |
|----|----------|---------|-----------|
| H1 | High | NATS port 4222 LAN-exposed (Docker bypasses UFW) | Rebound to 127.0.0.1; SSH tunnel for claudebox |
| M1 | Medium | OQP config chmod 644 | chmod 600 |
| M2 | Medium | CloudCLI accessible on storage network (<storage-subnet>) | UFW deny rule on enp4s0:3001 |
| M3 | Medium | NATS agent-research ACL overly broad (events.platform.>) | Removed from ACL; SIGHUP reload |
| M4 | Medium | Langfuse keys hardcoded in write-agent-envs.sh | Moved to /opt/secrets/langfuse.env |
| L1 | Low | PM2 script files chmod 755 | chmod 755 applied |
| L2 | Low | Secrets in appdata git history (2 commits) | Purged via git-filter-repo; force-pushed |
| L3 | Low | .gitignore missing credential patterns | Extended in both stacks and appdata repos |

**Stacks commits:** 765fce7 (gitignore), c5bb904 (NATS binding), 5d748dc (image pins + dockhand)  
**Appdata commits:** eda5dfa (nats.conf), 560263b (post-filter-repo HEAD)

## Claudebox Handoff

SSH tunnel for claudebox→NATS connectivity needed (NATS now localhost-only on forge). Handoff at `~/.claude/memory/shared/2026-05-16-helm-build-request-nats-tunnel.md`. All claudebox NATS publishing is blocked until tunnel is live.

## Image Pins

Hister and Dockhand images pinned to digest in compose files:
- `hister`: `sha256:ce5e7439…`
- `dockhand`: `sha256:e2434373…`

## Next Phase

Gateway build (`forge-phase6-gateway`) — awaiting build plan from research agent.
