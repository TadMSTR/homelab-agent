# Build: woodpecker-forge-2026-05

**Date:** 2026-05-31
**Agent:** sysadmin

Deployed Woodpecker CI v3.15.0 on forge with Gitea OAuth2 integration, SWAG reverse proxy, Authentik forward auth, per-stack Docker socket proxy, and scoped-mcp wiring for sysadmin, developer, and research agents.

---

## What Was Built

### Docker stack

Stack at `~/docker/woodpecker/` with three containers:

| Container | Purpose |
|-----------|---------|
| `woodpecker-server` | CI server; HTTP at `127.0.0.1:8100`; gRPC at `woodpecker-server:9000` (internal) |
| `woodpecker-agent` | Pipeline executor; connects to server via gRPC |
| `woodpecker-docker-proxy` | `tecnativa/docker-socket-proxy`; `EXEC=0`; agents use this for Docker access |

Network: `woodpecker-net` (internal). gRPC port 9000 not exposed to host.

### SWAG proxy config

NGINX config routes `ci.helmforge.me` → `127.0.0.1:8100`:
- Authentik forward auth on all paths
- `/api/hook` exact-match exemption for Gitea webhook delivery (not a wildcard bypass)

### Gitea OAuth2 wiring

OAuth2 application registered in Gitea admin. Client ID and secret stored in `woodpecker.env`. Webhooks activated on: `host-forge`, `host-forge-build-reports`, and docker stacks repos.

### githost-mcp integration

Woodpecker PAT added as `WOODPECKER_TOKEN` to githost-mcp env files. Enables full Woodpecker CI tool access for sysadmin and developer agents via `githost-mcp` v0.2.0:

| Agent | Access |
|-------|--------|
| sysadmin | Full: list, logs, trigger, status, cancel (HITL) |
| developer | Full: list, logs, trigger, status, cancel (HITL) |
| research | `woodpecker_status` only (trigger + cancel denylisted) |

Research agent uses a dedicated `githost-mcp-research.env` with `ALLOWED_REPO_ROOTS` restricted to `helm-platform` and `host-forge-scripts`.

---

## Key Decisions

**Per-stack docker socket proxy pattern established** — each Docker stack that needs Docker access gets its own `tecnativa/docker-socket-proxy` with minimal permissions, rather than mounting `docker.sock` directly. This replaces the single shared proxy approach. Pattern applies to all future stacks requiring Docker access.

**scoped-mcp v1.3.0 allowlist limitation (M-02 partial fix)** — scoped-mcp v1.3.0 does not support tool allowlists on proxy modules, only denylists. Research agent access is constrained via `tool_denylist` (blocking `woodpecker_trigger` and `woodpecker_pipeline_cancel`) rather than an explicit allowlist. Full allowlist support deferred pending future scoped-mcp release.

**I-03 / I-04 deferred** — log verbosity and pipeline cache TTL (info-level findings) deferred to a future hardening pass; no operational risk.

---

## Security Audit

11 findings: 0 critical, 0 high, 3 medium, 4 low, 4 info.

All 3 medium findings resolved:

| ID | Finding | Resolution |
|----|---------|-----------|
| M-01 | docker.sock mounted directly in agent container | Replaced with `woodpecker-docker-proxy` (`EXEC=0`) |
| M-02 | Research agent had access to destructive Woodpecker tools | `tool_denylist` applied; allowlist deferred (scoped-mcp limitation documented) |
| M-03 | `/api/hook` exemption scope too broad | Narrowed to exact-match only; not a wildcard bypass |

---

## Related Docs

- [woodpecker.md](../components/cicd/woodpecker.md) — component reference
- [githost-mcp.md](../components/mcp-servers/githost-mcp.md) — githost-mcp tool access details
- [agent-manifests.md](../../gitea/agent-platform/agent-manifests.md) — manifest HITL gate config
