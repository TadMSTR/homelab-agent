# Forge — Matrix/Synapse Homeserver

**Completed:** 2026-05-24
**Snapshots:** pre-matrix-synapse (in `/.snapshots/`)

## What Was Built

Full Matrix/Synapse homeserver stack on forge as the homelab-agent platform communications backbone.
Synapse v1.153.0 with PostgreSQL backend, SWAG reverse proxy with well-known delegation,
Ketesa admin UI gated by Authentik, and three PM2-managed services enabling agent-to-agent
Matrix communication.

The build establishes `helmforge.me` as the forge Matrix homeserver domain. All 5 forge
agents (sysadmin, research, dev, writer, security) have their scoped-mcp configs updated to
include the Matrix MCP endpoint, making Matrix messaging available as a tool surface across
the entire forge agent fleet.

## Components Deployed

| Service | Purpose | URL / Port |
|---------|---------|------------|
| Synapse | Matrix homeserver (v1.153.0) | `matrix.helmforge.me` |
| PostgreSQL | Synapse database backend | internal only (matrix-internal network) |
| Ketesa | Synapse admin UI | `ketesa.helmforge.me` (Authentik-gated) |
| matrix-mcp | MCP server bridging Matrix to forge agents | `127.0.0.1:8487` (PM2 id 20) |
| matrix-dispatcher | Routes incoming Matrix messages to forge agents | PM2 id 21 |
| matrix-admin-bot | Handles bot commands in Matrix rooms | PM2 id 22 |

## Network Architecture

Two Docker networks serve the stack:

- **forge-net** — shared proxy network; Synapse and Ketesa attach here for SWAG routing
- **matrix-internal** — isolated bridge for Synapse ↔ PostgreSQL; no external exposure

SWAG `default.conf` carries the well-known delegation entries (`/_matrix/key/v2/server`,
`/.well-known/matrix/server`, `/.well-known/matrix/client`) pointing to
`matrix.helmforge.me:443`. This enables federation and client discovery under the
`helmforge.me` server name while Synapse runs at `matrix.helmforge.me`.

## Matrix Infrastructure

**Homeserver:** `helmforge.me` (server at `matrix.helmforge.me`)

**Accounts created:**

| MXID | Role |
|------|------|
| `@ted:helmforge.me` | Synapse admin; allowed sender for matrix-admin-bot |
| `@forge-sysadmin:helmforge.me` | Forge sysadmin bot (matrix-dispatcher) |

**Rooms created (8):**

| Room | Purpose |
|------|---------|
| `#sysadmin:helmforge.me` | Sysadmin agent primary room |
| `#research:helmforge.me` | Research agent primary room |
| `#developer:helmforge.me` | Dev agent primary room |
| `#writer:helmforge.me` | Writer agent primary room |
| `#security:helmforge.me` | Security agent primary room |
| `#announcements:helmforge.me` | Platform-wide announcements |
| `#monitoring:helmforge.me` | Alerts and automated monitoring output |
| `#helm-build:helmforge.me` | Build agent output and build reports |

Registration is token-required — invite-only, managed via the Ketesa admin UI at
`ketesa.helmforge.me`.

## PM2 Agent Services

All three services are managed by PM2 on forge. Secrets are stored in `~/.secrets/`:

| Service | PM2 ID | Secrets file |
|---------|--------|-------------|
| matrix-mcp | 20 | `~/.secrets/matrix-mcp.env` |
| matrix-dispatcher | 21 | `~/.secrets/matrix-dispatcher.env` |
| matrix-admin-bot | 22 | `~/.secrets/matrix-admin-bot.yml` |

matrix-mcp uses FastMCP HTTP transport, listening on `127.0.0.1:8487`. All 5 forge
agent scoped-mcp configs register it as `http://localhost:8487/mcp`.

**Note:** matrix-dispatcher `config.yml` `project_dirs` entries are stubs pointing to
`/home/ted/.claude/projects/<agent>`. These will be wired after the `forge-agent-setup` build
provisions agent project directories on forge.

## Key Technical Findings

**Well-known delegation requires entries in `default.conf`, not a separate vhost:** Synapse's
well-known endpoints (`/.well-known/matrix/*`) must be served under the bare `helmforge.me`
domain, which is handled by SWAG's `default.conf`. A dedicated `matrix.conf` subdomain vhost
cannot serve these — they must live alongside the root domain configuration.

**PostgreSQL image must be SHA-pinned before first start:** The compose file uses a SHA digest
for the PostgreSQL image. If the digest is absent on first `docker compose up`, Synapse starts
before Postgres is healthy and fails with a connection error. Pin before starting, not after.

**matrix-internal network must be created before compose up:** The isolated bridge network
(`matrix-internal`) is declared as external in the compose file. Running `docker compose up`
without pre-creating it causes a network not found error. Create with
`docker network create --driver bridge matrix-internal` first.

**Ketesa requires a Synapse shared secret for admin operations:** Ketesa authenticates to
Synapse using a `registration_shared_secret` from `homeserver.yaml`. The secret must match
exactly — trailing whitespace in the YAML value causes silent auth failures in Ketesa.

## Security Audit Results

3 findings, all resolved.

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | `homeserver.yaml` world-readable — contains registration_shared_secret | `chmod 600 homeserver.yaml` in compose entrypoint (commit `c150af2`) |
| L1 | Low | PostgreSQL image not SHA-pinned | SHA digest added to compose file (commit `c150af2`) |
| L2 | Low | matrix-dispatcher git history contained plain-text bot token | Force-push to scrub history (commit `eb0f5ad`) |

## Next Steps

- Complete `forge-agent-setup` build to provision agent project directories on forge and wire
  matrix-dispatcher `project_dirs`
- Review and enable matrix-admin-bot room-specific command policies after agent setup
- Consider federation policy (currently open) — restrict to known homeservers if needed

## Related Docs

- [synapse.md](../components/synapse.md) *(homelab-agent — sanitized)*
- [matrix-mcp.md](../components/matrix-mcp.md) *(homelab-agent — sanitized)*
- [matrix-dispatcher.md](../components/matrix-dispatcher.md) *(homelab-agent — sanitized)*
- [matrix-admin-bot.md](../components/matrix-admin-bot.md) *(homelab-agent — sanitized)*
