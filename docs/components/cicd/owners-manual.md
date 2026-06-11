# Owner's Manual

The Owner's Manual is a living reference document for the homelab-agent platform, auto-generated from live system state by the docs agent (The Archivists). It covers hardware specs, running services, agent inventory, networking, backups, secrets layout, PM2 processes, update history, security posture, and troubleshooting.

## Infrastructure

| Component | Detail |
|-----------|--------|
| Git repo | `~/repos/personal/helm-owners-manual/` |
| Static site | `docs.helmforge.me` |
| Generator | mkdocs (Material theme, installed via pipx) |
| Reverse proxy | SWAG `docs.subdomain.conf` |
| Auth | Authentik forward auth (domain-level) |
| Serving path | `/config/www/owners-manual/` (SWAG container, static HTML) |

## Sections

10 markdown files in `docs/`, each representing a section of the manual:

| File | Content | Source |
|------|---------|--------|
| `system-specs.md` | CPU, RAM, disks, NICs, GPU | `/proc/cpuinfo`, `lscpu`, `lsblk`, `ip addr`, `free`, `uname` |
| `docker-stacks.md` | Running containers, ports, health, image versions | Docker API via docker-socket-proxy |
| `agent-inventory.md` | System and user agents, tiers, schedules, NATS subjects | `~/.helm/manifests/*.yaml` |
| `network.md` | IPs, NICs, DNS, reverse proxy routes | `ip`, SWAG proxy confs |
| `backup-status.md` | Last backup timestamps, next scheduled, coverage | Backup logs |
| `secrets-inventory.md` | Secret names and paths only (NEVER values) | Filesystem inspection |
| `pm2-services.md` | PM2 processes, cron schedules, log paths | `pm2 jlist` |
| `update-history.md` | Last update run, what changed, rollbacks | Update agent logs |
| `security-posture.md` | Firewall rules, AppArmor status, Authentik policies, TLS certs | `ufw status`, `aa-status` (sudo read-only) |
| `troubleshooting.md` | Common issues and quick fixes | Manual — preserved across regenerations |

## Regeneration Model

The docs agent regenerates sections from live system state — it reads the actual system, not previous output. This ensures the manual reflects reality, not accumulated prose drift.

- Auto-generated sections are marked with `<!-- AUTO-GENERATED — DO NOT EDIT -->` headers
- `troubleshooting.md` is the only manually-maintained section — never overwritten
- After writing markdown, the agent runs `mkdocs build` to regenerate static HTML
- Commits to git: `docs: regenerate <section> [<trigger>]`
- The `site/` directory is in `.gitignore` — only source markdown is committed

### Triggers

| Trigger | Scope | Source |
|---------|-------|--------|
| Daily schedule (05:00) | Full refresh — all 10 sections | PM2 cron |
| `events.platform.deployed` | Stack-specific sections | NATS event |
| `events.platform.config-changed` | Affected section only | NATS event |
| `tasks.docs.>` | On-demand via task queue | NATS task |

## SWAG Configuration

```nginx
server {
    listen 443 ssl;
    server_name docs.*;
    include /config/nginx/ssl.conf;
    include /config/nginx/authentik-server.conf;

    location / {
        include /config/nginx/authentik-location.conf;
        root /config/www/owners-manual;
        index index.html;
        try_files $uri $uri/ =404;
    }
}
```

Static files are served directly by nginx from the built mkdocs site — no upstream container or proxy_pass needed.

## mkdocs Configuration

```yaml
site_name: homelab-agent Owner's Manual
site_description: Auto-generated platform reference for homelab-agent on forge
theme:
  name: material
  palette:
    scheme: slate
    primary: blue grey
  features:
    - navigation.sections
    - navigation.expand
    - search.suggest
```

Installed via pipx: `~/.local/bin/mkdocs`

## Gotchas

- **Secrets inventory documents paths only** — the docs agent is prohibited from writing secret values. If a value appears in the manual, treat it as a security incident.
- **mkdocs build must run after writes** — markdown alone doesn't update the live site. The agent runs `mkdocs build` from the repo root after every commit.
- **SWAG serves from a static path** — the built site must be accessible at `/config/www/owners-manual/` inside the SWAG container (volume mount or copy).

## Related Docs

- system-agents — docs agent (The Archivists) role and constraints
- [phase-6-system-agents.md](../../phases/phase-6-system-agents.md) — Phase 6 context
- [authentik.md](../foundation/authentik.md) — forward auth configuration
