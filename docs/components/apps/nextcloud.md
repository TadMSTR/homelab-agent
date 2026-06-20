# Nextcloud

Self-hosted file sync, collaboration, and productivity platform on forge. Seven-container Docker stack with PostgreSQL, Valkey cache, OpenSearch full-text search, ClamAV antivirus, Collabora Online (document editing), and Nextcloud Whiteboard.

No Authentik forward auth — it breaks WebDAV clients and mobile sync apps. Each sub-service uses its own token-gating mechanism instead.

---

## Architecture

| Container | Image | Purpose |
|-----------|-------|---------|
| `nextcloud` | `lscr.io/linuxserver/nextcloud:latest` | Main app (nginx + php-fpm + notify_push via docker-mod) |
| `nextcloud-db` | `postgres:16-alpine` | Primary database |
| `nextcloud-valkey` | `valkey/valkey:8` | Session cache / file locking |
| `nextcloud-opensearch` | `opensearchproject/opensearch:2` | Full-text file search |
| `nextcloud-clamav` | `clamav/clamav:latest` | Antivirus scanning |
| `nextcloud-collabora` | `collabora/code:latest` | Nextcloud Office (LibreOffice Online) |
| `nextcloud-whiteboard` | `ghcr.io/nextcloud/whiteboard:latest` | Real-time collaborative whiteboard |

---

## Endpoints

| URL | Purpose | Auth |
|-----|---------|------|
| `https://nextcloud.helmforge.me` | Main web UI and WebDAV | Nextcloud login |
| `https://collabora.helmforge.me` | Collabora CODE document editor | Token-gated by Nextcloud |
| `https://whiteboard.helmforge.me` | Nextcloud Whiteboard | JWT-gated by Nextcloud |

All three are proxied by SWAG. Collabora admin console paths (`/browser/dist/admin`, `/cool/adminws`) are blocked at the proxy (403).

### Internal ports

| Container | Port | Protocol | Notes |
|-----------|------|----------|-------|
| `nextcloud` | 443 | HTTPS | LSIO image binds HTTPS internally |
| `nextcloud-collabora` | 9980 | HTTP | Collabora CODE API |
| `nextcloud-whiteboard` | 3002 | HTTP | Whiteboard WebSocket API |

OpenSearch (9200), ClamAV (clamd socket), and Valkey are on `nextcloud-internal` only — no host port binding.

---

## Networks

| Network | Purpose |
|---------|---------|
| `nextcloud-internal` | Isolated stack mesh — db, valkey, opensearch, clamav, collabora, whiteboard |
| `forge-net` | SWAG access for nextcloud main container, collabora, whiteboard |

The main `nextcloud` container joins both networks. The database, cache, search, and antivirus containers are `nextcloud-internal` only.

---

## Configuration

### Stack

- Stack directory: `~/docker/nextcloud/`
- Appdata: `/opt/appdata/nextcloud/`
  - `config/` — Nextcloud config and nginx/php config
  - `data/` — user files
  - `db/` — PostgreSQL data
  - `opensearch/` — OpenSearch indexes
  - `clamav/` — ClamAV virus definitions

### Environment

Secrets are in `~/docker/nextcloud/.env`. Key variables:

| Variable | Purpose |
|----------|---------|
| `NC_DB_PASSWORD` | PostgreSQL password |
| `NC_VALKEY_PASSWORD` | Valkey auth password |
| `NC_COLLABORA_ADMIN_PASSWORD` | Collabora admin console password |
| `NC_WHITEBOARD_JWT_SECRET` | Whiteboard JWT signing key |

Post-provisioning: `NC_ADMIN_PASSWORD` and install-time secrets are removed from the env file. App passwords for agents are in Vault at `secret/data/nextcloud/agents/<agent>`.

### LSIO docker-mod

The `nextcloud-notify-push` mod is loaded at startup. It provides the high-performance push notification daemon (`notify_push`) that Nextcloud apps use for live file-change events, avoiding polling.

### Resource limits

| Container | Memory | CPU |
|-----------|--------|-----|
| `nextcloud` | 2 GB | 2 cores |
| `nextcloud-db` | 1 GB | 1 core |
| `nextcloud-opensearch` | 1 GB | 1 core |
| `nextcloud-clamav` | 2 GB | 1 core |
| `nextcloud-collabora` | 1 GB | 2 cores |
| `nextcloud-valkey` | 512 MB | 0.5 cores |
| `nextcloud-whiteboard` | 512 MB | 0.5 cores |

### Extra hosts

The `nextcloud` and `nextcloud-whiteboard` containers have static host entries for `nextcloud.helmforge.me`, `collabora.helmforge.me`, and `whiteboard.helmforge.me` pointing to SWAG's forge-net IP (`172.20.1.29`). This ensures internal callbacks go through SWAG (required for SSL termination mode).

---

## Agent workspace

`/home/ted/.claude/comms/artifacts` is mounted read-write into the `nextcloud` container at `/agent-workspace`. This allows agents to share files with Nextcloud without network transfers.

`/home/ted/repos` and `/home/ted/Documents` are also mounted read-only at `/ted-personal/repos` and `/ted-personal/Documents`.

---

## Security notes

Several hardening trade-offs were accepted during the 2026-06-20 audit:

- **LSIO no-new-privileges** (F-06): LSIO's s6-overlay uses setuid at init; `user:` and `no-new-privileges` both break it. PUID/PGID=1000 drop is the LSIO-recommended mitigation.
- **PostgreSQL cap_drop** (F-06): PostgreSQL init runs as root to chown the data directory before dropping to the `postgres` user; `cap_drop: ALL` breaks it. `no-new-privileges` applied instead.
- **Valkey cap_drop** (F-06): Same pattern as PostgreSQL. `no-new-privileges` applied.
- **ClamAV cap_drop** (F-06): clamd/freshclam init requires root; `no-new-privileges` only.
- **Collabora cap_drop / no-new-privileges** (F-06): Collabora CODE's `coolforkit` uses chroot/setuid sandbox; needs `SYS_CHROOT`, `SETUID`, `SETGID`, `FOWNER`. Default Docker cap set required.
- **OpenSearch security plugin disabled** (F-09): No auth/TLS on OpenSearch. Accepted because it is on `nextcloud-internal` only — no host port, no forge-net access. Single-tenant forge; cert overhead exceeds risk.

---

## Operations

### Restart

```bash
cd ~/docker/nextcloud && docker compose down && docker compose up -d
```

### Health check

```bash
# Main app (self-reports running state)
curl -sk https://nextcloud.helmforge.me/status.php | python3 -m json.tool

# Database
docker exec nextcloud-db pg_isready -U nextcloud

# Containers
docker ps --filter name=nextcloud --format 'table {{.Names}}\t{{.Status}}'
```

### Logs

```bash
# Main app (nginx + php-fpm + notify_push)
docker logs nextcloud

# All stack containers
cd ~/docker/nextcloud && docker compose logs --tail=50
```

### OCC admin CLI

```bash
docker exec -u abc nextcloud php /config/www/nextcloud/occ <command>
# Example: check status
docker exec -u abc nextcloud php /config/www/nextcloud/occ status
```

### ClamAV signature update

ClamAV runs `freshclam` automatically on startup and periodically. Force an update:

```bash
docker exec nextcloud-clamav freshclam
```

---

## Dependencies

| Depends on | Why |
|------------|-----|
| `forge-net` | SWAG proxy access |
| SWAG | TLS termination, subdomain routing |

---

## Related docs

- [`docker/nextcloud/`](../../../docker/nextcloud/) — sample compose file
- [SWAG component doc](../foundation/swag.md)
- [stunnel component doc](stunnel.md) — SMTP relay used by Nextcloud for email notifications
