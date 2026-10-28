# Vaultwarden

Vaultwarden is a self-hosted Bitwarden-compatible password manager running on forge.
It provides secure credential storage accessible from any Bitwarden client.

- **Image:** `vaultwarden/server:latest`
- **URL:** `vault.example.com`
- **Appdata:** `/opt/appdata/vaultwarden/`
- **Network:** `forge-net`

## Configuration

| Setting | Value |
|---------|-------|
| `SIGNUPS_ALLOWED` | `false` — no self-registration |
| `INVITATIONS_ALLOWED` | `true` — invite-based onboarding |
| `SHOW_PASSWORD_HINT` | `false` |
| `LOG_LEVEL` | `warn` |

New accounts require an admin invitation. The admin panel is available at
`vault.example.com/admin` and is protected by a bcrypt-hashed admin token.

## Data

All Vaultwarden data (users, ciphers, attachments) is in `/opt/appdata/vaultwarden/`.
This directory is included in the forge backup schedule.

## Client Access

Use any Bitwarden-compatible client (browser extension, desktop app, mobile app) and
point it at `https://vault.example.com` as the server URL.

## Related Docs

- [swag.md](swag.md) — HTTPS termination via `vault.example.com`
- [vault.md](vault.md) — HashiCorp Vault (separate — secret management, not password manager)
