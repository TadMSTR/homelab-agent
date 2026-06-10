#!/bin/bash
# vault-seal-watcher.sh — Check Vault seal state; unseal if sealed.
# Run via PM2 cron every 5 minutes to recover from container restarts.
set -euo pipefail

VAULT_ADDR="http://localhost:8200"
LOG="$HOME/logs/vault-seal-watcher.log"
UNSEAL_SCRIPT="/usr/local/sbin/vault-auto-unseal.sh"

mkdir -p "$HOME/logs"

ts() { date -Iseconds; }

sealed=$(curl -s "$VAULT_ADDR/v1/sys/health" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(str(d.get('sealed','')).lower())" \
    2>/dev/null || echo "error")

case "$sealed" in
    false)
        echo "[$(ts)] Vault unsealed — OK" >> "$LOG"
        ;;
    true)
        echo "[$(ts)] Vault is sealed — running unseal script" >> "$LOG"
        if "$UNSEAL_SCRIPT" >> "$LOG" 2>&1; then
            echo "[$(ts)] Unseal succeeded" >> "$LOG"
        else
            echo "[$(ts)] ERROR: Unseal script failed" >> "$LOG"
            exit 1
        fi
        ;;
    *)
        echo "[$(ts)] WARNING: Could not reach Vault (response: $sealed)" >> "$LOG"
        ;;
esac
