# forge-reboot-gate

Gated daily reboot window that applies pending kernel updates without disrupting in-flight agent sessions. Implemented as a systemd timer that fires at 05:00 and reboots only when all safety gates pass.

## Components

| Component | Location |
|-----------|----------|
| systemd timer | `forge-reboot-window.timer` |
| systemd service | `forge-reboot-window.service` |
| Gate script | `/usr/local/bin/forge-reboot-gate.sh` |
| Log | `/var/log/forge-reboot-window.log` |

## Timer

```ini
[Timer]
OnCalendar=*-*-* 05:00:00
AccuracySec=1min
Persistent=true
```

`Persistent=true` — if the host was off at 05:00, the timer fires once on next boot.

## Safety gates

All three gates must pass for a reboot to proceed. Failure at any gate defers to the next 05:00 window.

| Gate | Condition | Fail behavior |
|------|-----------|---------------|
| 1 — kernel pending | `needrestart` kernel state ≥ 2 | Skip (exit 0) — no reboot needed |
| 2 — no agent session | No `claude` process under the operator user | Defer (exit 1) |
| 3 — dispatcher idle | `task-dispatcher` PM2 status is `stopped` | Defer (exit 1, fail-closed) |

Gate 1 uses `needrestart -p`. Kernel state values: 0 = current, 1 = ABI-compatible update, 2 = full kernel update pending. Only state ≥ 2 triggers the reboot path.

Gate 3 is fail-closed — unknown or error state (e.g. PM2 unavailable) is treated as a block, not a pass.

After reboot, PM2 and Docker services are resurrected by systemd. HashiCorp Vault requires manual unseal.

## Operations

Dry-run gate check:
```bash
sudo /usr/local/bin/forge-reboot-gate.sh --dry-run
```

View recent gate decisions:
```bash
tail -20 /var/log/forge-reboot-window.log
```

Timer status:
```bash
systemctl status forge-reboot-window.timer
```

Disable temporarily:
```bash
systemctl stop forge-reboot-window.timer
systemctl start forge-reboot-window.timer   # re-enable
```

## Dependencies

- `needrestart` — Gate 1 (`apt install needrestart`)
- `unattended-upgrades` — installs kernel updates (security pocket) that trigger Gate 1
- `pm2` — accessed as the operator user for Gate 3 dispatcher check
