# Vikunja

Self-hosted task/project management ([vikunja.io](https://vikunja.io)) on forge. A
three-container Docker stack — app, PostgreSQL-compatible database, and
[vikunja-mcp](../mcp-servers/vikunja-mcp.md) (agent tool access) — fronted by SWAG, paired
with [webhook-doorman](../agent/webhook-doorman.md) (its own Docker stack, GitHub → Vikunja
and Vikunja → Matrix/ntfy bridging). Two things worth knowing if this page was last read a
while ago: webhook-doorman replaced the standalone `vikunja-webhook-listener` PM2 service (no
such process exists anymore), and vikunja-mcp itself moved from a PM2 process to a container
in this same compose stack at v0.6.0 — a `vikunja-mcp` PM2 entry still shows in `pm2 jlist`
but is **stopped**, a dormant leftover (vikunja#468/#498, both still open), not the live
service.

---

## Architecture

| Container | Image | Purpose |
|-----------|-------|---------|
| `vikunja` | `vikunja/vikunja:latest` | App server — API + web UI |
| `vikunja-db` | `paradedb/paradedb:0.25.9-pg18` | PostgreSQL-compatible database |
| `vikunja-mcp` | `ghcr.io/tadmstr/vikunja-mcp:v0.11.0` | Agent MCP tool surface — moved here from PM2 at v0.6.0 |

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
| [webhook-doorman](../agent/webhook-doorman.md) | GitHub issues/PRs → Vikunja tasks; Vikunja task/reminder events → Matrix `#vikunja` / ntfy |

---

## Webhook bridging (webhook-doorman)

The GitHub↔Vikunja and Vikunja→Matrix/ntfy bridge is **webhook-doorman**, a Docker service —
not a PM2 process. It replaced the standalone `vikunja-webhook-listener` FastAPI service
(along with `qmd-webhook` and `plane-webhook-listener`) with one shared, fail-closed inbound
router. See [webhook-doorman.md](../agent/webhook-doorman.md) for the full source/sink model,
config, and content-safety layer; summary relevant to Vikunja:

| Direction | Path | Verification | Sink |
|-----------|------|---------------|------|
| GitHub → Vikunja | `/webhook/github` | HMAC-SHA256 (`X-Hub-Signature-256`) | `vikunja-chat` (Matrix) |
| Vikunja → Matrix/ntfy | `/webhook/vikunja` | HMAC-SHA256 (`X-Vikunja-Signature`) | `vikunja-chat` (Matrix), `push` (ntfy) |

Served behind SWAG at `vikunja-hooks.helmforge.me`, container port `127.0.0.1:8507` →
container `8080` (not 8502, the old listener's port). There is no `task.done` event — task
completion is inferred from `task.updated` with `done: true`.

---

## Operations

### Restart

```bash
cd ~/docker/vikunja && docker compose down && docker compose up -d
# vikunja-mcp is part of this same compose stack (moved off PM2 at v0.6.0) — no separate pm2 restart needed
# webhook-doorman is a separate stack — see webhook-doorman.md for its own restart command
```

### Health check

```bash
docker ps --filter name=vikunja --format 'table {{.Names}}\t{{.Status}}'
curl -s http://127.0.0.1:8501/health
curl -s http://127.0.0.1:8507/health   # webhook-doorman, not a Vikunja container
```

### Logs

```bash
docker logs vikunja --tail 50
docker logs vikunja-mcp --tail 50
docker compose -f ~/docker/webhook-doorman/docker-compose.yml logs -f webhook-doorman
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
`host-forge/vikunja-structure.md` (status: **ratified** 2026-07-07, provisioned 2026-07-14 —
the single source of truth for both vikunja-mcp's provisioning tools and the CloudCLI plugin).

---

## Related docs

- [vikunja-mcp](../mcp-servers/vikunja-mcp.md) — MCP wrapper over the Vikunja API
- [webhook-doorman](../agent/webhook-doorman.md) — GitHub/Vikunja webhook bridge (replaced `vikunja-webhook-listener`)
- `host-forge/vikunja-structure.md` — project taxonomy contract (ratified)
