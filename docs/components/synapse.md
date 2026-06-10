# Synapse (forge)

Synapse is the Matrix homeserver for the homelab-agent platform, running on forge and serving
`helmforge.me`. It provides the Matrix communications backbone for forge's operator
agents — the same role that claudebox's Synapse plays for claudebox agents, but scoped to
the forge environment.

See [matrix.md](../../../homelab-agent/docs/components/matrix.md) for the claudebox homeserver. This doc covers the forge
deployment only.

- **Version:** v1.153.0
- **Compose:** `~/docker/matrix/docker-compose.yml`
- **Appdata:** `/opt/appdata/matrix/`
- **Networks:** `forge-net` (SWAG proxy access) + `matrix-internal` (isolated bridge)

## Stack

| Container | Image | Purpose |
|-----------|-------|---------| 
| `synapse` | `matrixdotorg/synapse:v1.153.0` | Matrix homeserver, client API |
| `synapse-db` | `postgres` (SHA-pinned) | PostgreSQL backend |
| `ketesa` | `ghcr.io/etkecc/ketesa` (SHA-pinned) | Synapse admin UI (Authentik-gated) |

`synapse-db` is on `matrix-internal` only — not reachable from `forge-net` or outside the
stack. Synapse bridges the two networks: `matrix-internal` for the database connection,
`forge-net` for SWAG proxy access.

## SWAG Proxy

Three proxy confs serve the homeserver:

| Conf | Backend | Purpose |
|------|---------|---------| 
| `matrix.subdomain.conf` | `synapse:8008` | Client API (`/_matrix/`) |
| `ketesa.subdomain.conf` | `ketesa:8080` | Admin UI — Authentik forward auth |
| `default.conf` | (static) | `.well-known/matrix/client` and `.well-known/matrix/server` for domain delegation |

**Well-known delegation** in `default.conf` serves the Matrix discovery endpoints so that
clients can locate `matrix.helmforge.me` when connecting as `helmforge.me`. This
is required when the server name differs from the actual hostname.

Synapse's client API port (`8008`) is published only to `127.0.0.1` — not reachable from
the LAN directly. All access flows through SWAG.

## Configuration

Config at `/opt/appdata/matrix/synapse/homeserver.yaml` (chmod 600 — embedded secrets).

Key settings:
- `server_name: helmforge.me` — the Matrix domain, not the actual hostname
- `federation_enabled: false` — isolated homeserver, no federation with external servers
- `enable_registration: false` — new accounts require a registration token via Ketesa
- Database: PostgreSQL with `LC_COLLATE=C` and `LC_CTYPE=C` (required by Synapse)

Secrets in `homeserver.yaml` (`database.args.password`, `registration_shared_secret`,
`macaroon_secret_key`, `form_secret`) are sensitive — file permissions must stay at 600.

## Ketesa Admin UI

Ketesa is a web-based Synapse admin UI accessible at `ketesa.helmforge.me`, gated
by Authentik forward auth. It requires manual registration of an Authentik application and
provider before first use.

Ketesa is the primary interface for:
- Issuing registration tokens (invite-only signup)
- User and room administration
- Reviewing server state

## Accounts and Rooms

Agent bot accounts on the forge homeserver:
- `@forge-sysadmin:helmforge.me` — matrix-dispatcher bot (reads rooms, routes to agents)
- `@matrix-admin-bot:helmforge.me` — admin bot (account provisioning)
- Agent MXIDs follow the pattern `@agent.<type>:helmforge.me`

8 rooms created at build time: sysadmin, research, developer, writer, security,
announcements, monitoring, helm-build.

## Security

From audit 2026-05-24:

| Finding | Status |
|---------|--------|
| M1: `homeserver.yaml` world-readable (644) with embedded secrets | Fixed — `chmod 600` (commit `c150af2`) |
| L1: `postgres:16-alpine` tag-only (no digest) | Fixed — SHA-pinned in compose (commit `c150af2`) |
| L2: `matrix-dispatcher` git history contained internal MXID | Fixed — `git filter-repo` history scrub + force-push (`eb0f5ad`) |

Container hardening applied to all three containers: `no-new-privileges:true`, `cap_drop: ALL`
with minimal `cap_add`, memory limits (Synapse 2 GB, PostgreSQL 1 GB, Ketesa 64 MB).

## Related Docs

- [matrix-mcp-forge.md](matrix-mcp-forge.md) — MCP server for forge agent access
- [matrix-dispatcher-forge.md](matrix-dispatcher-forge.md) — message routing to forge agents
- [matrix-admin-bot-forge.md](matrix-admin-bot-forge.md) — account management bot
