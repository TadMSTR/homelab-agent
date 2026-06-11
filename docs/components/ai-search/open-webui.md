# Open WebUI

Open WebUI is the chat frontend for the forge platform. Users interact with gateway agents through Open WebUI; the UI sends requests to the Phase 6 gateway's `/v1` (OpenAI-compatible) endpoint, which routes to the appropriate per-user Claude runner.

- **Version:** `ghcr.io/open-webui/open-webui:main`
- **URL:** `https://open-webui.helmforge.me`
- **Compose:** `~/docker/open-webui/docker-compose.yml`
- **Appdata:** `/opt/appdata/open-webui/`
- **Network:** `forge-net`
- **SWAG proxy:** `open-webui.helmforge.me` → `open-webui:8080`

## Configuration

Key environment variables (set via `env_file: .env` in compose):

| Variable | Value | Notes |
|----------|-------|-------|
| `WEBUI_AUTH` | `true` | Required — enables login |
| `ENABLE_SIGNUP` | `false` | Prevents self-registration; accounts created by operator only |
| `WEBUI_SECRET_KEY` | (rotated) | JWT session signing key — in `~/docker/open-webui/.env` (chmod 600) |
| `OPENAI_API_BASE_URL` | `http://gateway:8000/v1` | Points to gateway (Phase 6 — not yet deployed) |

`.env` file is `chmod 600 ted:ted`. Never commit it to `host-forge/stacks`.

## Authentik OIDC (Pending)

Authentik OIDC wiring (Step 2c) was deferred from Phase 5 — it requires UI interaction in Authentik to create the OIDC provider. When ready:

1. In Authentik at `auth.helmforge.me`: create an OAuth2/OIDC provider for Open WebUI
2. Note the client ID and secret
3. In `~/docker/open-webui/.env`, add:
   ```
   OAUTH_CLIENT_ID=<id>
   OAUTH_CLIENT_SECRET=<secret>
   OAUTH_PROVIDER_NAME=Authentik
   OPENID_PROVIDER_URL=https://auth.helmforge.me/application/o/<slug>/.well-known/openid-configuration
   ```
4. Uncomment the `OAUTH_*` env vars block in `docker-compose.yml`
5. `docker compose up -d --force-recreate open-webui`

Until OIDC is wired, access is controlled by `WEBUI_AUTH=true` + `ENABLE_SIGNUP=false` with manually created accounts.

## Current Limitations

- **Gateway not deployed:** `OPENAI_API_BASE_URL` points to the Phase 6 gateway, which is not yet running. Attempting to chat will fail until Phase 6 is complete.
- **Unpinned image tag:** `ghcr.io/open-webui/open-webui:main` — accepted for initial deployment; pin to a versioned tag at next maintenance window.

## Security

| Finding | Status |
|---------|--------|
| H1: `WEBUI_SECRET_KEY` hardcoded in compose (committed to Gitea) | Fixed — key rotated, moved to `env_file`, commit `dbecf11` |
| No Authentik forward auth on SWAG proxy | Accepted — `WEBUI_AUTH=true` + `ENABLE_SIGNUP=false` is sufficient; Authentik OIDC pending |

## Related Docs

- [phase-5-user-stack-infra.md](../../phases/phase-5-user-stack-infra.md) — build narrative
- [authentik.md](../foundation/authentik.md) — OIDC provider (pending wiring)
