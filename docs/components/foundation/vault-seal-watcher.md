# vault-seal-watcher

vault-seal-watcher is a bash script that polls Vault's health endpoint every 5 minutes
and automatically unseals it when sealed. This fixes the nightly Docker backup issue where
Vault containers restart and come up sealed, blocking agents that depend on Vault secrets.

- **Script:** `~/scripts/vault-seal-watcher.sh`
- **Interpreter:** `bash`
- **Schedule:** PM2 cron, every 5 minutes (`*/5 * * * *`)
- **Log:** `~/logs/vault-seal-watcher.log`
- **No listening port** — runs as a batch job

## How It Works

1. Queries `http://localhost:8200/v1/sys/health` for the `sealed` field
2. If `false` — logs OK, exits
3. If `true` — runs `/usr/local/sbin/vault-auto-unseal.sh` to unseal, logs result
4. If unreachable — logs a warning (Vault container may be down)

## Configuration

| Setting | Value |
|---------|-------|
| Vault address | `http://localhost:8200` |
| Unseal script | `/usr/local/sbin/vault-auto-unseal.sh` |
| Log file | `~/logs/vault-seal-watcher.log` |
| Poll interval | 5 minutes (PM2 cron) |

## Dependencies

- **Vault** (port 8200) — the service being monitored
- **vault-auto-unseal.sh** — handles the actual unseal key submission

## Operations

```bash
# Check status
pm2 show vault-seal-watcher

# View logs
tail -20 ~/logs/vault-seal-watcher.log

# Force a check
pm2 restart vault-seal-watcher

# Manually check Vault seal state
curl -s http://localhost:8200/v1/sys/health | python3 -c "import sys,json; print(json.load(sys.stdin)['sealed'])"
```

## Related Docs

- [vault.md](vault.md) — Vault service configuration and operations
