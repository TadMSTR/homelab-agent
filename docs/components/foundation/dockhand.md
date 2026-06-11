# Dockhand

Dockhand is a web-based Docker stack management UI for forge. It provides visibility
into running containers, compose stacks, and image state, and exposes compose operations
(up, down, pull) through a browser interface.

- **Image:** `fnsys/dockhand` (SHA-pinned)
- **URL:** `dockhand.helmforge.me`
- **Port:** `127.0.0.1:7777` → container `3000`
- **Appdata:** `/opt/appdata/dockhand/`

## Volumes

| Mount | Purpose |
|-------|---------|
| `/var/run/docker.sock` | Docker API access |
| `~/docker` (read-only) | Compose file visibility |

`~/docker` is mounted read-only — Dockhand can read compose files to display stack
context but cannot modify them. All compose edits go through the normal git-tracked
workflow.

## Access

Dockhand is on `forge-net` and proxied through SWAG at `dockhand.helmforge.me`. Access
control is via SWAG proxy conf — it is not individually password-protected by the
application itself.

## Docker Socket Access

Dockhand connects directly to `docker.sock`. The `docker-proxy` socket proxy
(tecnativa/docker-socket-proxy) is also running on forge to provide filtered Docker API
access to other services. Dockhand uses the raw socket because it needs compose
operations, not just read access.

## User Context

Dockhand runs as `user: "1000:1000"` with `group_add: "989"` (the `docker` group GID on
forge) to allow socket access without running as root.

## Related Docs

- [swag.md](swag.md) — reverse proxy providing HTTPS access
