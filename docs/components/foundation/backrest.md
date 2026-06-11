# backrest

Backrest v1.13.0 is a web UI and scheduler for restic backups. On forge it runs as a
native systemd service (not Docker), backing up agent data, repos, secrets, and system
config to a restic repository on atlas NFS.

- **Binary:** `/usr/local/bin/backrest`
- **Service:** `/etc/systemd/system/backrest.service` (User=ted, `after=mnt-atlas-forge.mount`)
- **Config:** `~/.config/backrest/config.json`
- **Web UI:** `https://backrest.helmforge.me` (Authentik forward auth)
- **Port:** `9898` (`0.0.0.0`, UFW-restricted to <lan-subnet> + forge Docker networks)
- **Restic repo:** `atlas-forge` → `/mnt/atlas/forge/backups/restic` (NFS mount)

## Backup Plans

| Plan | Schedule | Paths | Retention |
|------|----------|-------|-----------|
| `forge-agent` | Daily 03:00 | `~/.claude/`, `~/scripts/`, `~/.config/` | 7d / 4w / 3m |
| `forge-repos` | Daily 03:30 | `~/repos/` | 7d / 4w |
| `forge-secrets` | Daily 04:00 | `~/.secrets/`, `~/.claude-secrets/`, `~/.config/backrest/` | 14d / 8w / 6m |
| `forge-system` | Weekly Sun 04:30 | `/etc/systemd/system/`, `/etc/cron.d/`, `/etc/cron.daily/`, `/etc/cron.weekly/` | 4w / 6m |

All plans target the single `atlas-forge` restic repo. Prune and check run monthly.

Common excludes across plans: `*/.memsearch/`, `*/__pycache__/`, `*/.venv/`, `*/node_modules/`, `*/build/`.

## Configuration

The service file sets the bind address via environment:

```ini
Environment="BACKREST_PORT=0.0.0.0:9898"
```

Config is in `~/.config/backrest/config.json`. The repo password is stored in the config
file (bcrypt-hashed auth for the web UI users).

Web UI users: `xadmin` (admin), `forge` (service account).

## Dependencies

- NFS mount `mnt-atlas-forge.mount` → `/mnt/atlas/forge` (required; systemd `After=` + `Requires=`)
- `restic` binary (used by backrest internally)
- `~/scripts/backrest-notify.sh` — Matrix notification hook on backup errors

## Operations

```bash
# Service status
systemctl status backrest

# Restart
sudo systemctl restart backrest

# Logs
journalctl -u backrest -f

# Trigger manual backup (via web UI or backrest CLI)
backrest backup --plan forge-agent
```

Alerts go to `#alerts:helmforge.me` on any `CONDITION_ANY_ERROR` via the hook command:
```
/home/ted/scripts/backrest-notify.sh '{{.Plan.Id}}' '{{.Error}}'
```

## Security Notes

- Binds `0.0.0.0:9898` — required for SWAG Docker→host routing (SWAG connects via `172.20.1.1`).
  UFW restricts inbound 9898 to <lan-subnet> and the Docker bridge networks.
  (Audit: 2026-06-03/backrest-forge-deploy-2026-06, accepted)
- Authentik forward auth on `backrest.helmforge.me` — all web UI access gated.
- Config file at `~/.config/backrest/config.json` contains the restic repo password
  (encrypted at rest via restic's own encryption, stored in bcrypt form for UI auth).
- Runs as `ted` (UID 1000) — same user as the backed-up paths.

## Related Docs

- `host-forge/backup-schedule.md` — full backup schedule reference across all forge backup mechanisms
- `host-forge/services.md` — port 9898 entry in the port registry
