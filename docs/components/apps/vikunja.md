# Vikunja

Self-hosted task/project management ([vikunja.io](https://vikunja.io)) on forge. A
two-container Docker stack (app + PostgreSQL-compatible database) fronted by SWAG, paired
with two PM2 services: [vikunja-mcp](../mcp-servers/vikunja-mcp.md) (agent tool access) and
`vikunja-webhook-listener` (GitHub → Vikunja and Vikunja → Matrix/ntfy bridging).

---

## Architecture

| Container | Image | Purpose |
|-----------|-------|---------|
| `vikunja` | `vikunja/vikunja:latest` | App server — API + web UI |
| `vikunja-db-1` | `paradedb/paradedb:latest` | PostgreSQL-compatible database |

Stack directory: `~/docker/vikunja/`. Appdata: `/opt/appdata/vikunja/` (`files/` for
attachments, `db/` for the database volume).

---

## Endpoints

| URL / bind | Purpose | Auth |
|------------|---------|------|
| `https://vikunja.helmforge.me` | Web UI + REST API (`/api/v1`) | Local login or OIDC (Authentik) |
| `127.0.0.1:8501` | [vikunja-mcp](../mcp-servers/vikunja-mcp.md) — MCP tool surface for agents | Per-agent bearer token (passthrough) |

Vikunja does **not** sit behind Authentik forward auth — it has its own local login and an
OpenID Connect provider (`authentik`) configured for SSO. Registration is disabled;
accounts are provisioned manually (Ted + 5 agent service accounts).

---

## Configuration

Key `~/docker/vikunja/docker-compose.yml` settings (env vars in `~/docker/vikunja/.env`):

- `VIKUNJA_DB_PASSWORD`, `VIKUNJA_SERVICE_SECRET` — core secrets
- `VIKUNJA_OIDC_CLIENT_ID` / `VIKUNJA_OIDC_CLIENT_SECRET` — Authentik OIDC app credentials
- `VIKUNJA_WEBHOOKS_ENABLED: "true"` — required for `vikunja-webhook-listener` delivery
- `VIKUNJA_OUTGOINGREQUESTS_ALLOWNONROUTABLEIPS: "true"` — deliberately relaxes Vikunja's
  SSRF guard (blocks RFC1918 targets by default in v2.2+) so webhook delivery can reach the
  internal `vikunja-webhook-listener`. Safe here because webhook registration is restricted
  to trusted accounts only (Ted + agents), not open to untrusted users.
- `extra_hosts` pins `auth.helmforge.me` and `vikunja-hooks.helmforge.me` to SWAG's
  `forge-net` IP (`172.20.1.29`) — forge's hairpin-NAT limitation means the container can't
  reach those public hostnames via the LAN gateway otherwise.

---

## Dependencies

| Depends on | Why |
|------------|-----|
| `vikunja-db-1` | Primary datastore |
| SWAG + `forge-net` | TLS termination and subdomain routing |
| Authentik | OIDC SSO provider |

| Depended on by | How |
|----------------|-----|
| [vikunja-mcp](../mcp-servers/vikunja-mcp.md) | Wraps the API at `127.0.0.1:8501` for agents (stateless token passthrough) |
| `vikunja-webhook-listener` (PM2) | GitHub issues/PRs → Vikunja tasks; Vikunja task/reminder events → Matrix `#vikunja` / ntfy |

---

## vikunja-webhook-listener

FastAPI service, PM2-managed, `0.0.0.0:8502` (behind SWAG at `vikunja-hooks.helmforge.me`).
Bridges two independent directions, each HMAC-verified and **fail-closed** — an unset secret
disables that direction entirely (`401`) rather than skipping verification:

| Direction | Trigger | Action |
|-----------|---------|--------|
| GitHub → Vikunja | Issue/PR `opened` | Creates a Vikunja task via `GITHUB_PROJECT_MAP` |
| Vikunja → Matrix | `task.created`, `task.updated` (done:true), `task.comment.created` | Posts to Matrix `#vikunja` |
| Vikunja → ntfy | `task.reminder.fired`, `task.overdue`, `tasks.overdue` (user webhooks, not project webhooks) | Push notification |

Repo: `~/repos/personal/vikunja-webhook-listener/`. There is no `task.done` event — task
completion is inferred from `task.updated` with `done: true`.

---

## Operations

### Restart

```bash
cd ~/docker/vikunja && docker compose down && docker compose up -d
pm2 restart vikunja-mcp vikunja-webhook-listener
```

### Health check

```bash
docker ps --filter name=vikunja --format 'table {{.Names}}\t{{.Status}}'
curl -s http://127.0.0.1:8501/health
curl -s http://127.0.0.1:8502/health
```

### Logs

```bash
docker logs vikunja --tail 50
pm2 logs vikunja-mcp --lines 50
pm2 logs vikunja-webhook-listener --lines 50
```

---

## scoped-mcp integration

`vikunja-mcp` is wired into all 5 agent manifests (`~/.claude/manifests/*.yml`) as an
`mcp_proxy` module pointing at `http://127.0.0.1:8501/mcp`. Each agent injects its own
Vikunja API token as `Authorization: Bearer ${VIKUNJA_TOKEN}` — vikunja-mcp holds no
credentials itself and forwards the token verbatim, so every call is attributable to the
calling agent inside Vikunja. Per-agent tool allowlists (sysadmin: unrestricted; others:
project/task/label/comment subsets) are documented in
[vikunja-mcp.md](../mcp-servers/vikunja-mcp.md).

Project taxonomy, identifier scheme, and label conventions are defined in
`host-forge/vikunja-structure.md` (status: **proposed**, not yet ratified).

---

## Related docs

- [vikunja-mcp](../mcp-servers/vikunja-mcp.md) — MCP wrapper over the Vikunja API
- `host-forge/vikunja-structure.md` — project taxonomy contract (proposed)
