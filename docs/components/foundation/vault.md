# Vault

HashiCorp Vault 1.19, deployed as the secrets backend for the forge platform. Stores gateway credentials (Claude OAuth tokens per user) under AppRole auth. Required by the Phase 6 gateway before it can retrieve per-user credentials.

- **Version:** 1.19
- **URL:** `https://hvault.helmforge.me`
- **Compose:** `~/docker/vault/docker-compose.yml`
- **Config:** `/opt/appdata/vault/config/vault.hcl`
- **Appdata:** `/opt/appdata/vault/`
- **Network:** `forge-net`
- **Credentials:** `~/.claude-secrets/vault.env` (root token, unseal key, AppRole role-id/secret-id)

## Configuration

`vault.hcl` (file storage backend, TLS disabled at service level — SWAG terminates TLS):

```hcl
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://vault:8200"
```

## Compose Gotchas

Several non-obvious requirements discovered during deployment:

| Gotcha | Correct approach |
|--------|-----------------|
| Config volume mount | Must NOT be `:ro` — Vault writes lock files to the config directory |
| Container CMD | Must be overridden to `server`; the default entrypoint alone is insufficient |
| Data directory ownership | uid=100 must own `/vault/data` — `chown 100:100 /opt/appdata/vault/data` before first start |
| `VAULT_LOCAL_CONFIG` env var | Do NOT set — conflicts with the mounted `vault.hcl` config file |

## Unseal Procedure

Vault does **not** auto-unseal. It starts sealed after every container restart or host reboot. In sealed state, all API requests return 503.

```bash
source ~/.claude-secrets/vault.env
docker exec vault vault operator unseal $VAULT_UNSEAL_KEY
# Confirm: docker exec vault vault status | grep Sealed
```

The unseal key is stored in `~/.claude-secrets/vault.env`. Do not lose this file — there is no other recovery path for the file storage backend without the key.

## AppRole Auth

Vault uses AppRole auth for gateway access. The gateway authenticates with `role-id` + `secret-id` (both in `vault.env`) to obtain a short-lived token, then reads/writes credentials under a namespaced path.

AppRole credentials are in `~/.claude-secrets/vault.env`:
```
VAULT_ROOT_TOKEN=...
VAULT_UNSEAL_KEY=...
VAULT_APPROLE_ROLE_ID=...
VAULT_APPROLE_SECRET_ID=...
```

## Security

| Finding | Status |
|---------|--------|
| TLS disabled at service level (L3) | Accepted — SWAG terminates TLS at edge; traffic within Docker network is unencrypted but isolated |
| No forward auth on SWAG proxy | Accepted — Vault token auth is sufficient; UI access is operator-only |

SWAG proxy (`hvault.subdomain.conf`) routes to `vault:8200`. No Authentik gate — Vault's own auth is the boundary.

## Related Docs

- [phase-5-user-stack-infra.md](../../phases/phase-5-user-stack-infra.md) — build narrative
- [authentik.md](authentik.md) — identity provider (Authentik is not used for Vault auth)
