# stunnel

`stunnel4` is a native system service that wraps Proton Mail Bridge's local SMTP port with a valid Let's Encrypt certificate. This allows apps that reject self-signed certificates (Authentik, Dockhand, Nextcloud) to use Proton Mail Bridge as an SMTP relay without per-app certificate exceptions.

---

## Architecture

```
client (SSL/TLS, implicit, LE cert)
    → 0.0.0.0:1587 (stunnel4)
        → 127.0.0.1:1025 (Proton Mail Bridge, STARTTLS, self-signed)
```

The frontend (client-facing) side uses implicit TLS. stunnel handles the STARTTLS handshake for the backend (Bridge) leg using `protocol = smtp`. Clients connect with SSL/TLS mode, not STARTTLS.

---

## Configuration

**Config file:** `/etc/stunnel/proton-smtp.conf`

```ini
[smtp]
accept   = 0.0.0.0:1587
connect  = 127.0.0.1:1025
protocol = smtp
cert     = /opt/appdata/swag/etc/letsencrypt/live/helmforge.me/fullchain.pem
key      = /opt/appdata/swag/etc/letsencrypt/live/helmforge.me/privkey.pem
sslVersionMin = TLSv1.2
```

The cert is the SWAG-managed wildcard Let's Encrypt cert for `*.helmforge.me` (ECDSA chain via YE1/Root YE/ISRG Root X2).

---

## Service

stunnel4 runs as a native `systemd` service (generated from the SysV init script):

```bash
sudo systemctl status stunnel4
sudo systemctl restart stunnel4
```

---

## Firewall rules

| Rule | Command | Why |
|------|---------|-----|
| LAN hosts | `ufw allow from 192.168.1.0/24 to any port 1587 proto tcp` | Allows LAN devices to relay |
| Docker containers | `ufw route allow from 172.20.1.0/24 to 192.168.1.12 port 1587 proto tcp` | Docker FORWARD chain (INPUT rule has no effect for container→host traffic) |

Docker container traffic to the host's LAN IP (`192.168.1.12`) goes through the nftables FORWARD chain, not INPUT. `ufw route allow` is required; `ufw allow from` alone is not sufficient.

---

## Certificate renewal

stunnel auto-reloads when the SWAG cert renews. Two systemd units handle this:

**`/etc/systemd/system/stunnel-cert-reload.path`** — watches the cert file:
```ini
[Path]
PathChanged=/opt/appdata/swag/etc/letsencrypt/live/helmforge.me/fullchain.pem
```

**`/etc/systemd/system/stunnel-cert-reload.service`** — reloads stunnel4 on path change:
```ini
[Service]
ExecStart=/bin/systemctl reload stunnel4
```

No manual cert rotation needed. SWAG renews the cert; the path unit triggers stunnel reload automatically.

---

## Dependencies

| Depends on | Why |
|------------|-----|
| Proton Mail Bridge | Backend SMTP relay on 127.0.0.1:1025 |
| SWAG LE cert | `/opt/appdata/swag/etc/letsencrypt/live/helmforge.me/` — cert and key |
| UFW | Port 1587 firewall rules for LAN and Docker FORWARD chain |

---

## Operations

### Restart

```bash
sudo systemctl restart stunnel4
```

### Force cert reload (manual)

```bash
sudo systemctl reload stunnel4
```

### Verify TLS

```bash
openssl s_client -connect forge.helmforge.me:1587 -quiet
# Should show ISRG Root X2 / Let's Encrypt chain
```

### Logs

```bash
sudo journalctl -u stunnel4 -f
```

---

## Related docs

- [Proton Mail Bridge component doc](proton-bridge.md)
- [SWAG component doc](../foundation/swag.md) — source of the LE cert
