# Forge Phase 1 — Atlas Gitea Org & Repo Setup

**Completed:** 2026-05-12
**Security audit:** forge-phase1-gitea-setup — 3 findings (M1, L1, L2), all resolved

## What Was Built

Three private Gitea organisations and 11 repositories scaffolded on atlas Gitea (`gitea.tadmstr.me`). Four repos received seed content. This is the foundational git hosting layer — every subsequent forge build phase depends on the repo structure established here. No services were started; this phase is pure git hosting scaffolding.

## Org Layout

| Org | Purpose |
|-----|---------|
| `agent-platform` | Platform-wide, host-agnostic content: KB, canonical agent/skill definitions, shared compose templates, platform docs |
| `host-forge` | Forge-specific operational content: KB, compose files, scripts, build history, agent activity logs |
| `users` | Per-user gateway config repos: one per platform user, holds CLAUDE.md, agent definitions, skill overrides, personal KB |

## Repositories

### agent-platform (5 repos)

| Repo | Purpose | Seeded |
|------|---------|--------|
| `knowledge-base` | Platform-wide KB: host-agnostic design patterns, agent model, onboarding | Skeleton README; content added in Phase 2 |
| `agents` | Canonical agent definitions for all platform users | Empty; populated in Phase 5 |
| `skills` | Canonical skills shared across the platform | Empty; populated in Phase 5 |
| `compose` | Shared Docker Compose templates and Dockerfiles | `templates/forge-stack.yml` + README |
| `docs` | Platform design docs and ADRs | Empty |

### host-forge (5 repos)

| Repo | Purpose | Seeded |
|------|---------|--------|
| `knowledge-base` | Forge operating environment KB: hardware, network, services, paths, users | Skeleton README; content added in Phase 2 |
| `stacks` | Forge's actual compose files and `.env` templates | Empty |
| `scripts` | Forge deploy and backup scripts | Empty |
| `build-reports` | Forge build history | Empty |
| `agent-activity` | Forge agent operational logs | Empty |

### users (1 repo)

| Repo | Purpose | Seeded |
|------|---------|--------|
| `ted-gateway-config` | Ted's per-user gateway config (first platform user) | `CLAUDE.md`, `agents/`, `skills/`, `knowledge/`, `config/scoped-mcp.json` |

## Downstream Phase Dependencies

| Phase | Dependency on Phase 1 |
|-------|----------------------|
| Phase 2 (KB seeding) | `agent-platform/knowledge-base`, `host-forge/knowledge-base` repos exist and are cloneable |
| Phase 5 (first user stack) | `users/ted-gateway-config` exists with CLAUDE.md + bootstrap directory structure |

## Seeded Content Details

**`agent-platform/compose`** — `templates/forge-stack.yml` provides the standard stack template for new forge services: `forge-net` network attachment, `/opt/appdata/<stack>/<service>/` volume convention, `TZ=America/New_York` env baseline.

**`users/ted-gateway-config`** — Bootstrap structure only; agent definitions and personal KB are empty at this phase. `config/scoped-mcp.json` grants access to forge MCP tools (`agent-bus`, `searxng`, `scoped-mcp`) with placeholder URLs to be populated during Phase 5 stack deployment. `CLAUDE.md` defines runner identity, gateway URL, and KB mount paths.

## Credentials

- Gitea admin PAT: `~/.claude-secrets/gitea-admin.env` on forge (`chmod 600`, directory `700`)
- Required scopes: `read:org`, `write:org`, `read:repo`, `write:repo`
- Token is needed for future phases — do not rotate without updating the file
- Git global identity set on forge: `user.name = Ted`, `user.email = pmurray@pm.me`

## Security Audit

3 findings, all resolved:

| ID | Severity | Finding | Resolution |
|----|----------|---------|-----------|
| M1 | Medium | Cloudflare API token in `~/.bash_history` on forge (line 14, bare CLI arg) | Token rotated in Cloudflare dashboard; line 14 purged from bash_history |
| L1 | Low | Residual `/tmp/test_gitea.sh`, `test_gitea2.sh` not cleaned up after build | Files removed from forge |
| L2 | Low | `/tmp` files created with world-readable/executable permissions | `umask 027` added to `~/.bashrc` on forge |

No credentials committed to any repo. `gitea-admin.env` permissions confirmed `600`/directory `700`. PAT scope confirmed: admin API endpoints return 403 (token is not admin-scoped). No new public-facing surface — Gitea on atlas is internal-only.

## Next Phase

**Phase 2 — KB Seeding:** Initial content committed to `agent-platform/knowledge-base` and `host-forge/knowledge-base`, curated from `ted/prime-directive`.
