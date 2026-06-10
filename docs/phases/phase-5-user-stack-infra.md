# Forge Phase 5 — User Stack Infrastructure

**Completed:** 2026-05-13
**Snapshots:** pre-phase5 (btrfs), post-phase5 (btrfs)
**Security audit:** forge-phase5-user-stack-infra — 8 findings (2H, 2M, 4L); 2H + 2M fixed, 3L accepted

## What Was Built

Full user-facing service stack on forge: Vault (secrets backend), Open WebUI (chat frontend), the 4-container Firecrawl scraping stack, FlashRank reranker, Crawl4ai, scoped-mcp venv, and searxng-mcp npm global install. SearXNG migrated from valkey → Dragonfly (platform Dragonfly in `agent-platform` stack). Two hardcoded secrets in Gitea-committed compose files were caught by security audit and remediated before the phase closed.

## Services Deployed

| Service | Version | Role |
|---------|---------|------|
| Vault | 1.19 | Secrets backend — AppRole auth for gateway (Phase 6) |
| Open WebUI | ghcr.io/…:main | Chat frontend — wires to gateway `/v1` endpoint |
| Firecrawl | 0.0.46 | 4-container web scraping stack |
| FlashRank reranker | custom | Query result reranker (Jina-compatible `/v1/rerank`) |
| Crawl4ai | 0.8.6 | Browser-based content extraction |
| scoped-mcp | venv | Scoped MCP control plane — `/opt/venvs/scoped-mcp/` |
| searxng-mcp | npm global | MCP server wiring SearXNG + Firecrawl + reranker + Crawl4ai |

## Web Search Pipeline

```
agent (via scoped-mcp)
  └─► searxng-mcp (npm global, /opt/tools/searxng-mcp/)
        ├─► SearXNG          — web search index query
        ├─► Firecrawl        — fast HTML scraping + content extraction
        ├─► Crawl4ai         — browser rendering for JS-heavy pages
        └─► Reranker         — FlashRank /v1/rerank result scoring
```

`run-forge.sh` at `/opt/tools/searxng-mcp/run-forge.sh` starts searxng-mcp with the correct env vars. `CRAWL4AI_API_TOKEN` is read at runtime from `~/.claude-secrets/crawl4ai.env` (not hardcoded). SearXNG now uses the `agent-platform` Dragonfly instance for its cache (valkey retired from the searxng stack).

## User Layout

Ted's per-user state is at `/opt/appdata/users/ted/`. `sync-user-configs.sh` runs every 5 minutes (cron) to sync `users/ted-gateway-config` from atlas Gitea into the working directory that the runner container mounts.

## Vault Unseal Procedure

Vault does **not** auto-unseal. After every forge reboot:

```bash
source ~/.claude-secrets/vault.env
docker exec vault vault operator unseal $VAULT_UNSEAL_KEY
```

Vault is sealed state = operational but requests fail. Gateway (Phase 6) will fail to retrieve credentials until unsealed. Monitor at `https://hvault.helmforge.me`.

## Pending: Open WebUI Authentik OIDC

OIDC wiring (Step 2c) was deferred — requires creating an OIDC provider in Authentik UI at `auth.helmforge.me`. Once done:
1. Uncomment `OAUTH_*` env vars in `~/docker/open-webui/docker-compose.yml`
2. `docker compose up -d --force-recreate open-webui`

Open WebUI is currently accessible with `WEBUI_AUTH=true`, `ENABLE_SIGNUP=false` — only manually created accounts work.

## Security Audit Summary

| ID | Severity | Finding | Resolution |
|----|----------|---------|-----------|
| H1 | High | `WEBUI_SECRET_KEY` hardcoded in compose, committed to Gitea | Key rotated; moved to `~/docker/open-webui/.env` (env_file), compose updated, open-webui redeployed |
| H2 | High | `CRAWL4AI_API_TOKEN` hardcoded in compose + run-forge.sh, committed to Gitea | Token rotated; moved to `~/docker/crawl4ai/.env` (env_file); run-forge.sh reads from `~/.claude-secrets/crawl4ai.env` at runtime |
| M1 | Medium | sync-user-configs.sh chmod 775 | `chmod 750` applied |
| M2 | Medium | `COREPACK_INTEGRITY_KEYS=0` in firecrawl without explanation | Explanatory comment added to compose |
| L1 | Low | Unpinned image tags (open-webui:main, searxng:latest) | Accepted — pin at next maintenance window |
| L2 | Low | Firecrawl no API auth | Accepted — forge-net only, no external exposure |
| L3 | Low | Vault TLS disabled | Accepted — SWAG terminates TLS at edge |
| L4 | Low | `~/docker/` dirs chmod 775 | `chmod 750` applied to new stack dirs |

Post-triage canonical compose source: commit `dbecf11` on `host-forge/stacks`.

## Next Phase

**Phase 6 — Vault + Gateway Service + Open WebUI Wiring:** Deploy FastAPI gateway with `/v1/*` (OpenAI-compatible) and `/auth/*` (Claude token management UI). Wire Vault AppRole for credential storage. Connect Open WebUI to `/v1` endpoint.
