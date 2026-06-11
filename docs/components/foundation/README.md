# Foundation — Host, Networking & Auth

Core infrastructure that everything else depends on: reverse proxy, SSL termination, authentication, secret management, backups, and host-level maintenance.

Deploy these first. The rest of the stack assumes SWAG is routing traffic and Authentik is handling auth.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [swag.md](swag.md) | SWAG nginx reverse proxy | 80, 443 |
| [authentik.md](authentik.md) | SSO — forward auth + OIDC | 9000, 9443 |
| [vault.md](vault.md) | HashiCorp Vault — secret management | 8200 |
| [vaultwarden.md](vaultwarden.md) | Bitwarden-compatible password manager | 8343 |
| [dockhand.md](dockhand.md) | Docker stack manager UI | 7777 |
| [forge-configs.md](forge-configs.md) | Host configuration management | — |
| [backrest.md](backrest.md) | Backup scheduler (restic → NFS) | 9898 |
| [btrbk-daily.md](btrbk-daily.md) | Btrfs snapshot scheduler | — (cron) |
| [btrfs-scrub-monthly.md](btrfs-scrub-monthly.md) | Btrfs filesystem maintenance | — (cron) |
| [vault-seal-watcher.md](vault-seal-watcher.md) | Vault seal monitor → Matrix alert | — (PM2) |

## Deployment Order

1. SWAG (SSL + routing)
2. Authentik (SSO)
3. Vault (secrets)
4. Vaultwarden (passwords)
5. Dockhand (stack management)
6. Host maintenance jobs (backrest, btrbk, vault-seal-watcher)
