# Ollama Queue Proxy

Ollama Queue Proxy (OQP) is a queuing, auth, and routing layer in front of Ollama. It enforces per-client API keys, limits concurrency, prioritizes requests, and caches embedding results. All forge services that call Ollama go through OQP rather than hitting `ollama:11434` directly.

- **Image:** `ghcr.io/tadmstr/ollama-queue-proxy:0.3.0`
- **Compose:** `~/docker/agent-platform/docker-compose.yml`
- **Config:** `/opt/appdata/agent-platform/ollama-queue-proxy/config.yml`
- **Credentials:** `~/.claude-secrets/oqp-forge.env`
- **Networks:** `forge-net` (proxy) + `oqp-internal` (isolated, Valkey only)

## Stack

| Container | Image | Purpose |
|-----------|-------|---------|
| `ollama-queue-proxy` | `ghcr.io/tadmstr/ollama-queue-proxy:0.3.0` | Proxy — queuing, auth, routing, embedding cache |
| `oqp-valkey` | `valkey/valkey:8-alpine` | Embedding cache backend (Redis-compatible) |

`oqp-valkey` is on `oqp-internal` only — not reachable from `forge-net`. OQP bridges both networks.

## Ports

| Port | Purpose |
|------|---------|
| `127.0.0.1:11435` | Main proxy port — queued Ollama API requests |
| `127.0.0.1:11436` | Client injection port — no live client as of the 2026-09-17 memsearch retirement (`memsearch-watch-fast`/`memsearch-watch-templates`, split from `memsearch-watch` 2026-07-20, were its only users — see [memsearch.md](../memory/memsearch.md#retirement)) |

No SWAG proxy — both ports are localhost-only.

## Routing

OQP routes to a single upstream Ollama instance (`http://ollama:11434`, named `forge-local`) with a max concurrency of 2. Strategy is `model_aware` with `any_healthy` fallback.

## Auth

API key auth is required. Keys are stored in `~/.claude-secrets/oqp-forge.env`. Each client has a named key with a priority tier and optional concurrency limit:

| Client ID | Priority | Notes |
|-----------|----------|-------|
| `open-webui` | high | Open WebUI web interface |
| `admin` | high | Admin / orchestration; management enabled |
| `agent-research` | normal | Research agent embeddings |
| `agent-sysadmin` | normal | Sysadmin agent |
| `searxng-mcp` | normal | SearXNG MCP LLM calls (expand + summarize) |
| `hister` | low | Hister semantic search embeddings |
| `memsearch-watch` | low | **Retired 2026-09-17** with memsearch — no process holds this client identity today (neither `memsearch-watch-fast` nor `memsearch-watch-templates` exists in `pm2 jlist`). Config entry not independently reverified as removed; treat as a likely residual, not a live client. |

`memsearch-watch-fast` and `memsearch-watch-templates` used to connect on port 11436 (injection port) and be automatically identified as the `memsearch-watch` client — no API key needed on that port. That was the only user of the injection port; qmd's local embedding model doesn't go through OQP at all. See [memsearch.md](../memory/memsearch.md#retirement).

## Embedding Cache

OQP caches embedding vectors in Valkey to avoid redundant Ollama calls:

| Setting | Value |
|---------|-------|
| Backend | `redis://oqp-valkey:6379/0` |
| TTL | 86400 s (24 hours) |
| Max entry | 32 KB |
| Key prefix | `oqp:embed:` |

## Security

Container hardening: `read_only: true`, `tmpfs: /tmp`, `no-new-privileges:true`, `cap_drop: ALL`, `user: 1000:1000`.

## Related Docs

- [ollama.md](ollama.md) — Ollama backend that OQP proxies
- [memsearch.md](../memory/memsearch.md) — retired 2026-09-17; used the OQP injection port for
  embeddings while live, no longer a client
