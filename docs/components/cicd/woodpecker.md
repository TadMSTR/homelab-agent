# Woodpecker CI

Woodpecker is a lightweight CI/CD engine integrated with the forge Gitea instance. It runs pipelines defined in `.woodpecker.yml` files in Gitea repositories, triggered by webhooks on push, PR, and tag events.

- **Version:** 3.15.0
- **URL:** `https://ci.helmforge.me`
- **Compose:** `~/docker/woodpecker/docker-compose.yml`
- **Appdata:** `/opt/appdata/woodpecker/`
- **Network:** `woodpecker-net` (internal) + `forge-net` (server only)
- **SWAG proxy:** `ci.helmforge.me` → `woodpecker-server:8000`

## Stack

Three services: CI server, pipeline agent, and a filtered Docker socket proxy.

| Container | Image | Role |
|-----------|-------|------|
| `woodpecker-server` | `woodpeckerci/woodpecker-server:v3.15.0` | Web UI, API, webhook receiver — port 8000 (mapped to 127.0.0.1:8100) |
| `woodpecker-agent` | `woodpeckerci/woodpecker-agent:v3.15.0` | Pipeline runner — connects to server on gRPC port 9000 |
| `woodpecker-docker-proxy` | `tecnativa/docker-socket-proxy:latest` | Filtered Docker API access for the agent |

## Appdata Layout

```
/opt/appdata/woodpecker/
├── server/                   → /var/lib/woodpecker (woodpecker.db — SQLite)
└── agent/                    → /etc/woodpecker
```

## Configuration

**Database:** SQLite3 at `/var/lib/woodpecker/woodpecker.db` (persisted to appdata).

**Gitea integration:** Woodpecker authenticates to Gitea as an OAuth application. Repos with `.woodpecker.yml` are auto-discovered.

- `WOODPECKER_GITEA=true`
- `WOODPECKER_GITEA_URL` — Gitea instance URL
- `WOODPECKER_GITEA_CLIENT` / `WOODPECKER_GITEA_SECRET` — OAuth credentials

**Registration:** Closed (`WOODPECKER_OPEN=false`). Admin user set via `WOODPECKER_ADMIN`.

**Agent concurrency:** `WOODPECKER_MAX_PROCS=2`

**Secrets file:** `~/.secrets/woodpecker.env` (chmod 600) — contains OAuth credentials, agent secret, admin user, and PAT.

## Docker Socket Proxy

The agent does not mount the Docker socket directly. Instead, it connects through `woodpecker-docker-proxy` which filters Docker API calls:

**Allowed:** containers, images, volumes, networks, post, info, ping, events, version
**Blocked:** exec, build, swarm, secrets, services, nodes, plugins, commit, session, restarts, start, stop

This prevents pipeline steps from exec-ing into host containers or accessing Docker secrets.

## Authentication

- **Web UI:** Authentik forward auth via SWAG
- **Webhook endpoint:** `/api/hook` (POST) is exempt from forward auth — Gitea needs direct access to deliver webhooks

## Security

- Both server and agent: `cap_drop: ALL`, `security_opt: no-new-privileges:true`
- Resource limits: server 512MB / 0.5 CPU, agent 2GB / 2.0 CPU
- Docker socket proxy limits API surface available to pipeline steps

## Dependencies

- **Gitea** — source of repos, webhooks, and OAuth authentication
- **SWAG** — reverse proxy and SSL termination
- **Authentik** — forward auth for web UI

## Operations

**Restart stack:**
```bash
docker compose -f ~/docker/woodpecker/docker-compose.yml down && docker compose -f ~/docker/woodpecker/docker-compose.yml up -d
```

**View logs:**
```bash
docker logs woodpecker-server --tail 50
docker logs woodpecker-agent --tail 50
```

**Health check:** `docker inspect woodpecker-server --format '{{.State.Health.Status}}'` — should return `healthy`.
