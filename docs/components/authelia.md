# Authelia

Authelia is the SSO authentication gateway that protects every web-accessible service in the stack. One login, one session cookie, access to everything behind SWAG. It uses a file-based user backend with argon2id password hashing — no LDAP server, no external identity provider needed.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) alongside [SWAG](swag.md), which handles the actual proxying. Authelia makes the access control decisions; SWAG enforces them.

## Why Authelia

I needed authentication that worked across all services without configuring auth individually in each one. Authelia integrates with SWAG out of the box — two `include` lines in a proxy conf and the service is protected. No per-service OIDC setup, no shared auth databases, no middleware chains to debug.

The file-based user backend is the right fit for a single-user or household setup. It's a YAML file with usernames and argon2id-hashed passwords. For a homelab with 1-3 users, this is simpler and more reliable than standing up LDAP or connecting to an external IdP. Authelia also supports LDAP and OIDC if you outgrow the file backend.

I looked at Authentik as an alternative. It's more feature-rich (full IdP, SCIM, application management) but also heavier — multiple containers, PostgreSQL, Redis. For "put a login page in front of my services," Authelia is the right weight.

## What's in the Stack

Authelia runs as a single container with a SQLite database for session and authentication state. No external dependencies.

| Container | Image | Purpose | RAM |
|-----------|-------|---------|-----|
| authelia | authelia/authelia:4.38 | Auth gateway + session management | ~50MB |

It joins the shared Docker network and exposes port 9091 internally (not to the host). SWAG proxies `auth.yourdomain` to it. See [`docker/authelia/docker-compose.yml`](../../docker/authelia/docker-compose.yml) for the compose file.

## Configuration

Authelia's config lives at `/config/configuration.yml` inside the container (mapped from `/opt/appdata/authelia/` on the host). Here's a sanitized version of the key sections:

```yaml
server:
  address: 'tcp://:9091/authelia'

log:
  level: info

identity_validation:
  reset_password:
    jwt_secret: 'YOUR_JWT_SECRET'     # Generate with: openssl rand -hex 64

authentication_backend:
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 3
      key_length: 32
      salt_length: 16
      memory: 65536
      parallelism: 4

session:
  secret: 'YOUR_SESSION_SECRET'       # Generate with: openssl rand -hex 64
  cookies:
    - domain: 'yourdomain'
      authelia_url: 'https://auth.yourdomain/authelia'
      default_redirection_url: 'https://yourdomain'

storage:
  encryption_key: 'YOUR_ENCRYPTION_KEY'  # Generate with: openssl rand -hex 64
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt

access_control:
  default_policy: one_factor
  rules:
    - domain: '*.yourdomain'
      policy: one_factor
```

The `notifier.filesystem` section writes password reset notifications to a file instead of sending email. For a household setup where you have direct access to the host, this is fine — check `/config/notification.txt` for reset links. Switch to SMTP if you want email delivery.

### User Database

The user database is a YAML file at `/config/users_database.yml`:

```yaml
users:
  youruser:
    displayname: "Your Name"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..."   # See below
    email: user@example.com
    groups:
      - admins
```

Generate the password hash with Authelia's built-in tool:

```bash
docker exec authelia authelia crypto hash generate argon2 --password 'your-password'
```

### Access Control

The config above uses a blanket `one_factor` policy for all subdomains. This means a single username/password login with no MFA. For a homelab on an internal network with no internet exposure, this is reasonable — the domain doesn't resolve outside your network anyway.

If you want per-service policies (e.g., two-factor for sensitive services), Authelia supports that through additional `access_control.rules` entries.

## Integration Points

Authelia's primary integration is with [SWAG](swag.md). The flow works like this: a request hits SWAG for `chat.yourdomain`, SWAG's nginx checks with Authelia via a subrequest (`/api/authz/forward-auth`), Authelia validates the session cookie, and if valid, SWAG proxies the request through to the container. If not valid, the user is redirected to the Authelia login page at `auth.yourdomain`.

Adding Authelia protection to any SWAG-proxied service requires two lines in the proxy conf:

```nginx
# In the server block:
include /config/nginx/authelia-server.conf;

# In the location block:
include /config/nginx/authelia-location.conf;
```

SWAG ships these snippet files pre-configured. No manual nginx auth configuration needed.

## Gotchas and Lessons Learned

**The session cookie domain must match.** The `session.cookies.domain` in Authelia's config must match the base domain used by all your services. If your services are at `*.yourdomain` but the cookie domain is set to something else, SSO won't work — each service will prompt for login independently.

**The `/authelia` path prefix matters.** The `server.address` config includes `/authelia` as a path prefix. The `authelia_url` in the session config must include this: `https://auth.yourdomain/authelia`. If these don't match, the auth redirect loop fails silently.

**SQLite locking on slow storage.** Authelia uses SQLite for session storage. If your appdata volume is on slow storage (NFS, spinning disk), you might see intermittent "database is locked" errors under concurrent logins. Local SSD storage avoids this entirely. For higher concurrency, Authelia also supports PostgreSQL and MySQL backends.

**Generate all secrets before first start.** Authelia refuses to start with empty or default secrets. Generate `jwt_secret`, `session.secret`, and `storage.encryption_key` before the first `docker compose up`. The `openssl rand -hex 64` command works for all three.

## Standalone Value

SWAG + Authelia is useful for any Docker homelab, not just this AI platform. If you run multiple services and want a single login across all of them without configuring auth in each service individually, this pair solves it cleanly. The file-based user backend means zero additional infrastructure — no database server, no LDAP, no external IdP.

## Further Reading

- [Authelia documentation](https://www.authelia.com/)
- [Authelia + SWAG integration guide](https://www.authelia.com/integration/proxies/swag/)
- [Authelia configuration reference](https://www.authelia.com/configuration/prologue/introduction/)
- [Authelia file-based user provider](https://www.authelia.com/configuration/first-factor/file/)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where Authelia fits in the three-layer stack
- [SWAG](swag.md) — the reverse proxy that enforces Authelia's access decisions
- [Docker compose file](../../docker/authelia/) — Authelia stack compose
