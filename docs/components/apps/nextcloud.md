# Nextcloud

Self-hosted file sync, collaboration, and productivity platform on forge. Seven-container Docker stack with PostgreSQL, Valkey cache, OpenSearch full-text search, ClamAV antivirus, Collabora Online (document editing), and Nextcloud Whiteboard.

No Authentik forward auth — it breaks WebDAV clients and mobile sync apps. Each sub-service uses its own token-gating mechanism instead.

---

## Architecture

| Container | Image | Purpose |
|-----------|-------|---------|
| `nextcloud` | `lscr.io/linuxserver/nextcloud:35.0.2-ls460` | Main app, Nextcloud 35 (nginx + php-fpm + notify_push via docker-mod) |
| `nextcloud-db` | `postgres:16.15-alpine` | Primary database |
| `nextcloud-valkey` | `valkey/valkey:8` | Session cache / file locking |
| `nextcloud-opensearch` | `opensearchproject/opensearch:2` | Full-text file search |
| `nextcloud-clamav` | `clamav/clamav:1.5.4` | Antivirus scanning |
| `nextcloud-collabora` | `collabora/code:26.04.3.2.1` | Nextcloud Office (LibreOffice Online) |
| `nextcloud-whiteboard` | `ghcr.io/nextcloud/whiteboard:v2.1.2` | Real-time collaborative whiteboard (backend paired with whiteboard app 2.1.x) |

Images are pinned to version tags. Valkey and OpenSearch still follow a major tag. Nextcloud
can't skip a major release, so upgrade one major at a time, and reach the latest point release
of the current major first. Since LinuxServer moved its main tag line to 35, the 34.x builds
ship only on its `previous-` tag line.

---

## Endpoints

| URL | Purpose | Auth |
|-----|---------|------|
| `https://nextcloud.example.com` | Main web UI and WebDAV | Nextcloud login |
| `https://collabora.example.com` | Collabora CODE document editor | Token-gated by Nextcloud |
| `https://whiteboard.example.com` | Nextcloud Whiteboard | Websocket JWT-gated by Nextcloud; `/status` is public |

All three are proxied by SWAG. Collabora admin console paths (`/browser/dist/admin`, `/cool/adminws`) are blocked at the proxy (403).

**Whiteboard server-side recording is disabled on purpose.** The v2 backend's recorder runs a
headless Chromium without a sandbox, and anyone holding a write JWT can start it, including
anyone with an edit-enabled public share link. The compose disables it by pointing
`CHROME_EXECUTABLE_PATH` at a path that doesn't exist. That one value is the whole control, and
it fails open if someone empties it or upstream renames the variable. So after every whiteboard
deploy or image bump, check that the recorder reports itself unavailable.

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
| `nextcloud-internal` | Isolated stack mesh — nextcloud, db, valkey, opensearch, clamav, collabora |
| `forge-net` | SWAG access for the nextcloud main container, collabora and whiteboard |

The main `nextcloud` container and collabora join both networks. The database, cache, search
and antivirus containers are on `nextcloud-internal` only.

The whiteboard is on `forge-net` **only**. It reaches Nextcloud through SWAG at its public URL
(`NEXTCLOUD_URL`), and SWAG reaches it on `forge-net`. It used to be on `nextcloud-internal`
too, which put an internet-reachable service next to the unauthenticated OpenSearch, clamd,
Valkey and PostgreSQL.

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

Post-provisioning: `NC_ADMIN_PASSWORD` and install-time secrets are removed from the env file. No agent or service holds a Nextcloud app password.

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

---

## Agent workspace

The agents' shared artifacts directory on the host is bind-mounted **read-only** (`:ro`) into
the `nextcloud` container at `/agent-workspace`. It appears as the "Agent Workspace" External Storage mount, applied to the
operator and to an `agents` group that holds one Nextcloud account per agent. Agents write
artifacts on the host, and people read them in Nextcloud through web links. The `:ro` bind is
the write control. Agents read that tree as instructions, so code execution in this
internet-facing container must not be able to change it. Nextcloud's own `readonly` mount option
is only a permissions mask. `files:scan` writes only to the database, so indexing still works.

The operator's `~/Documents` is mounted read-write as a second External Storage mount, for the
operator only. It holds ordinary user files.

**There is no repos mount.** An earlier `~/repos` mount was removed. It exposed scripts that cron
runs, and live credentials in checked-out repos, to a web app. Browse repos in a code forge (Gitea
or GitHub) instead of mounting them into Nextcloud.

### Agent access

Agents have **no Nextcloud API access**: no MCP server, no app passwords, no WebDAV. They keep
their Nextcloud accounts only so that the Agent Workspace mount, which is applied to their group,
works for the web links they send. A dedicated Nextcloud MCP server
(nextcloud-mcp) was retired; see [nextcloud-mcp.md](../nextcloud-mcp.md).

The sysadmin agent operates the stack through an allowlisted `occ` wrapper script, with a skill
and a runbook. Read commands run directly. Write commands need the operator's approval of the
exact command line. User management, `config:*:set`, `app:install`, encryption, and enabling or
disabling security apps are refused, and stay with the operator.

---

## Security notes

Several hardening trade-offs were accepted during the 2026-06-20 audit:

- **LSIO no-new-privileges** (F-06): LSIO's s6-overlay uses setuid at init; `user:` and `no-new-privileges` both break it. PUID/PGID=1000 drop is the LSIO-recommended mitigation.
- **PostgreSQL cap_drop** (F-06): PostgreSQL init runs as root to chown the data directory before dropping to the `postgres` user; `cap_drop: ALL` breaks it. `no-new-privileges` applied instead.
- **Valkey cap_drop** (F-06): Same pattern as PostgreSQL. `no-new-privileges` applied.
- **ClamAV cap_drop** (F-06): clamd/freshclam init requires root; `no-new-privileges` only.
- **Collabora cap_drop / no-new-privileges** (F-06): Collabora CODE's `coolforkit` uses chroot/setuid sandbox; needs `SYS_CHROOT`, `SETUID`, `SETGID`, `FOWNER`. Default Docker cap set required.
- **OpenSearch security plugin disabled** (F-09): No auth/TLS on OpenSearch. Accepted because it is on `nextcloud-internal` only — no host port, no forge-net access. Single-tenant forge; cert overhead exceeds risk. This is also why the whiteboard is not on `nextcloud-internal` any more.

Lessons from the 2026-10 stack review:

- **Keep the whiteboard recorder disabled**, and check it after every bump (see Endpoints).
- **Don't mount source repos into a web app.** Browse them in a code forge.
- **Review every bind mount of a web-facing container**, for executables that something else
  runs and for secrets it could read, not only the mount a finding names. Each fix in that
  review uncovered the next exposure on a neighbouring mount.

---

## Operations

### Restart

```bash
cd ~/docker/nextcloud && docker compose down && docker compose up -d
```

### Health check

```bash
# Main app (self-reports running state)
curl -sk https://nextcloud.example.com/status.php | python3 -m json.tool

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
docker exec -u abc nextcloud php /app/www/public/occ --no-ansi <command>
# Example: check status
docker exec -u abc nextcloud php /app/www/public/occ --no-ansi status
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
