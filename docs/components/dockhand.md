# Dockhand

Dockhand is a web-based Docker Compose stack manager. It gives you a visual interface for viewing container status, reading logs, and managing Docker Compose stacks without SSH access. Think of it as a lighter alternative to Portainer that's focused specifically on Compose workflows.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, accessible at `dockhand.yourdomain` behind SWAG + Authelia.

## Why Dockhand

I wanted a way to quickly check container status and read logs from a phone or tablet without opening an SSH session. Portainer is the obvious choice here but it's heavier than what I needed — Dockhand is a single container that does the 80% case (view stacks, check status, read logs, restart containers) without the user management, registries, and deployment features that Portainer bundles.

Dockhand also has a nice feature for multi-host setups: it can read compose files from NFS-mounted directories, giving you visibility into stacks running on other hosts. In my setup, I mount atlas's Docker compose directory read-only so I can see what's running there without SSH-ing over.

## What's in the Stack

Single container, minimal footprint:

| Container | Image | Purpose | RAM |
|-----------|-------|---------|-----|
| dockhand | fnsys/dockhand:latest | Docker stack manager UI | ~80MB |

See [`docker/dockhand/docker-compose.yml`](../../docker/dockhand/docker-compose.yml) for the compose file.

## Prerequisites

- Docker CE + Compose
- Access to the Docker socket (required for container management)

## Configuration

Dockhand's configuration is minimal — most of it is in the compose file itself.

### Docker Socket Access

Dockhand needs the Docker socket mounted to manage containers. The `group_add` directive in the compose file must match your host's Docker group GID:

```bash
# Find your docker group GID:
getent group docker | cut -d: -f3
```

Put that GID in the compose file's `group_add` field. This is host-specific — it varies between distros and installations.

### Volume Mounts for Stack Discovery

Dockhand discovers Compose stacks by scanning mounted directories for `docker-compose.yml` files. Mount the directories where your compose files live:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
  - /opt/appdata/dockhand:/opt/appdata/dockhand
  - /home/youruser/docker:/home/youruser/docker        # Local stacks
  # Optional: mount remote compose files via NFS for cross-host visibility
  # - /mnt/remote-host/stacks:/mnt/remote-host/stacks:ro
```

The NFS mount is optional but useful in multi-host setups. Mount the remote host's compose file directory read-only and Dockhand will show those stacks in the UI (though it can only manage containers on the local Docker socket).

## Gotchas and Lessons Learned

**Docker socket GID varies by host.** The most common GIDs are 999, 998, and 984. Don't assume — always check with `getent group docker`. If the GID is wrong, Dockhand starts but can't list or manage containers.

**Home directory mount is broad.** The compose file mounts the user's home directory so Dockhand can find compose files scattered across `~/docker/` subdirectories. If you'd rather be more restrictive, mount only the specific directories where your compose files live.

**Port 3000 conflicts.** Dockhand listens on port 3000, which is a common default for many web apps. If you have another service on 3000, remap in the compose file: `"3100:3000"` or similar. The SWAG proxy conf points to the container port (3000), not the host mapping, so changing the host port doesn't break reverse proxy access.

**WebSocket support in proxy conf.** Dockhand uses WebSockets for live container log streaming. The SWAG proxy conf needs `Upgrade` and `Connection` headers set, or log streaming falls back to polling.

## Standalone Value

Dockhand is completely independent of every other component in this stack. It's a generic Docker Compose UI that works with any Docker host. If you want a lightweight web interface for managing your Docker stacks and you don't need Portainer's full feature set, Dockhand is worth a look.

## Further Reading

- [Dockhand GitHub](https://github.com/fnsys/dockhand)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where Dockhand fits in the three-layer stack
- [SWAG](swag.md) — reverse proxy and SSL for `dockhand.yourdomain`
- [Authelia](authelia.md) — SSO protecting the Dockhand UI
- [Docker compose file](../../docker/dockhand/) — Dockhand stack compose
