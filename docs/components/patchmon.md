# PatchMon

PatchMon is a self-hosted patch management platform that tracks apt packages across enrolled
hosts and surfaces available updates, CVEs, and patch history through a web UI. It replaces
PatchPilot on forge.

- **Image:** `patchmon/server:2.0.2` (SHA-pinned in compose)
- **Compose:** `~/docker/patchmon/docker-compose.yml`
- **Appdata:** `/opt/appdata/patchmon/`
- **Network:** `forge-net` (SWAG access)
- **URL:** `https://patchmon.helmforge.me`
- **API docs:** `https://patchmon.helmforge.me/api-docs` (Swagger/OpenAPI)

## Stack Containers

| Container | Image | Role |
|-----------|-------|------|
| `patchmon-server` | `patchmon/server:2.0.2` | Main application server |
| `patchmon-postgres` | `postgres:17-alpine` | Relational data store |
| `patchmon-valkey` | `valkey:8-alpine` | Cache / job queue |
| `patchmon-guacd` | `guacamole/guacd:1.6.0` | Guacamole daemon (remote terminal in UI) |

All four images are SHA-pinned (L1, resolved at build).

## Authentication

PatchMon uses **native OIDC** — it handles its own JWT validation rather than relying on
Authentik forward-auth. SWAG acts as a plain reverse proxy (no `authelia-location.conf`
snippet in the proxy conf). The Authentik application is configured as an OIDC provider;
PatchMon's `OIDC_*` environment variables point to Authentik's discovery endpoint.

This means:
- No Authentik-specific proxy conf header required
- Session tokens are managed by PatchMon, not Authentik
- The SWAG conf is a standard `proxy_pass http://patchmon-server:<port>` block

## Hairpin DNS

PatchMon-server must resolve `auth.helmforge.me` to complete OIDC flows. Since both
`patchmon-server` and the Authentik container are behind SWAG on the same forge host,
a hairpin DNS workaround is required:

```yaml
extra_hosts:
  - "auth.helmforge.me:172.20.1.20"
```

`172.20.1.20` is SWAG's IP on `forge-net`. Without this, OIDC token exchange fails because
the container cannot resolve the external FQDN back to the local SWAG instance.

## Host Agent

Forge is enrolled as a managed host via the PatchMon outbound agent. The agent connects
**outbound only** via WebSocket — no inbound port is opened:

- **Connection:** `wss://patchmon.helmforge.me/api/v1/agents/ws`
- **Registered:** 1943 packages, 8 repos on first check-in (2026-05-25)
- No persistent daemon required — agent runs as a system service that maintains the
  WebSocket connection

## Migration from PatchPilot

PatchPilot was fully decommissioned as part of this build:
- Container stopped and removed
- Host agent service removed
- SWAG proxy conf (`patchpilot.subdomain.conf`) removed
- Appdata archived at `/opt/appdata/patchpilot-archived/`

The patchpilot MCP build plan is now obsolete — a **patchmon-mcp** wrapping
`/api/v1` (Swagger at `/api-docs`) is the Phase 5 successor.

## Security

From audit 2026-05-25 (2 Low findings, both resolved):

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| L1 | Low | Stack images not SHA-pinned | SHA digests added to all 4 images in compose |
| L2 | Low | Archived PatchPilot appdata contained credentials | `shred -u` run on credential files before archiving |

## Related Docs

- [patchmon-mcp.md](patchmon-mcp.md) — MCP server for PatchMon API
- [renovate.md](renovate.md) — companion non-Docker update scanner
