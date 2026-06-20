# Proton Mail Bridge

Proton Mail Bridge is a native desktop application that provides a local SMTP/IMAP interface to Proton Mail accounts. On forge it runs as a Cinnamon DE startup application and exposes SMTP on `127.0.0.1:1025`. Other services connect through stunnel (see [stunnel.md](stunnel.md)) to get a properly signed TLS endpoint.

---

## Architecture

Proton Mail Bridge is not containerized. It runs as a native Linux process under the `ted` user session, started automatically via the Cinnamon Startup Applications manager.

```
app / container
    → SMTP to 127.0.0.1:1587 (stunnel, implicit TLS, LE cert)
        → stunnel → 127.0.0.1:1025 (Bridge, STARTTLS, self-signed)
            → Proton Mail API (cloud)
```

---

## Endpoints

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `127.0.0.1:1025` | SMTP + STARTTLS (self-signed cert) | Bridge's local SMTP listener |
| `forge.helmforge.me:1587` | SMTP over SSL/TLS (LE cert via stunnel) | What apps connect to |

Apps should connect to port **1587** via stunnel, not 1025 directly. Bridge's self-signed cert is rejected by most apps.

---

## App SMTP settings

| Setting | Value |
|---------|-------|
| Host | `forge.helmforge.me` |
| Port | `1587` |
| Encryption | SSL/TLS (implicit — **not** STARTTLS) |
| Username | Proton Mail address |
| Password | Bridge-generated SMTP password (not the Proton Mail login password) |

The Bridge-generated password is available in the Bridge UI or Bitwarden.

---

## Startup

Bridge auto-starts via Cinnamon Startup Applications:

- Desktop entry: `~/.config/autostart/Proton Mail Bridge.desktop`
- Requires an active desktop session (not a headless boot)
- If the desktop session is not running, Bridge is not available and SMTP will fail

To start manually:

```bash
/home/ted/.local/share/protonmail/bridge-v3/updates/3.25.0/proton-bridge --no-window
```

---

## Configuration

Bridge persists its config and keychain credentials at:

- `~/.config/protonmail/`
- `~/.local/share/protonmail/`

The logged-in account and Bridge password are stored in the system keyring. Re-login is required if the keyring is cleared or the session is reset.

---

## Services configured

| Service | Config location |
|---------|----------------|
| Dockhand | Settings UI → Notifications → SMTP (forge.helmforge.me:1587) |
| Authentik | `~/docker/authentik/.env` — `AUTHENTIK_EMAIL__*` vars on server and worker |
| Nextcloud | Nextcloud admin → Email server settings |

---

## Operations

### Check Bridge is running

```bash
pgrep -a proton-bridge
```

### Verify SMTP relay

```bash
openssl s_client -connect forge.helmforge.me:1587 -quiet
```

### Restart Bridge

1. Kill the existing process: `pkill proton-bridge`
2. Re-launch via the Cinnamon Startup Applications entry or the manual command above
3. Verify with `pgrep -a proton-bridge`

---

## Dependencies

| Depends on | Why |
|------------|-----|
| Cinnamon desktop session | Bridge is a GUI app; requires an active user session |
| stunnel | Wraps Bridge's self-signed cert with a real LE cert for apps |
| SWAG LE cert | Cert used by stunnel (via symlinks in `/opt/appdata/swag/etc/letsencrypt/`) |

---

## Related docs

- [stunnel component doc](stunnel.md) — TLS wrapping for Bridge's SMTP port
