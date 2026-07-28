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
| `127.0.0.1:11436` | Client injection port — `memsearch-watch-fast` and `memsearch-watch-templates` (split from `memsearch-watch` 2026-07-20) connect here and are injected under the same client identity |

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
| `graphiti` | normal | Graphiti knowledge graph embeddings |
| `hister` | low | Hister semantic search embeddings |
| `memsearch-watch` | low | Embedding indexer — shared client identity for `memsearch-watch-fast` and `memsearch-watch-templates` (split from `memsearch-watch` 2026-07-20); max 2 concurrent, uses injection port |

`memsearch-watch-fast` and `memsearch-watch-templates` connect on port 11436 (injection port) and are automatically identified as the `memsearch-watch` client — no API key needed on that port. The injection port is the isolation layer; `allow_public_injection: true` in the config reflects this.

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
- [memsearch.md](../memory/memsearch.md) — uses OQP injection port for embeddings
