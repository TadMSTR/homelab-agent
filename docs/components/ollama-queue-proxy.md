# ollama-queue-proxy

Smart pool manager for Ollama. One proxy process in front of the Ollama fleet — authenticates requests with per-client keys, queues by priority tier, routes to the host with the model already loaded, caches repeated embedding calls in Valkey, and enforces per-client concurrency caps.

**Version:** 0.2.0 | **Source:** [TadMSTR/ollama-queue-proxy](https://github.com/TadMSTR/ollama-queue-proxy)

## Why It's Here

Claudebox runs several Ollama consumers simultaneously: graphiti (background knowledge graph ingestion), jobsearch-mcp (bge-m3 embeddings), searxng-mcp (query expansion and summarization via qwen3), memsearch-watch (continuous memory indexing), and interactive sessions via LibreChat and Open WebUI. Without coordination, a long batch job can stall interactive requests for minutes.

The proxy puts auth, queuing, and routing in front of all consumers without touching consumer code. Each client gets its own key with a priority ceiling and a concurrency cap. A background job running at `low` priority can never starve an interactive request at `normal` or `high`.

## Deployment

Docker stack on claudebox. Config in `/opt/appdata/ollama-queue-proxy/config.yml` (chmod 600, gitignored).

| Port | Binding | Purpose |
|------|---------|---------|
| 11435 | 127.0.0.1:11435 | Main proxy — all authenticated Ollama requests |
| 11436 | 127.0.0.1:11436 | Injection port — memsearch-watch (no Bearer support) |

Fronted by the local SWAG instance for internal service-to-service access. No Authelia — consumers authenticate directly with their Bearer token; SSO is not appropriate for machine-to-machine calls.

**Network:** Valkey sidecar runs on a dedicated `oqp-internal` Docker network alongside the proxy. The cache is not exposed externally.

## Auth Model

Seven clients provisioned across three priority tiers:

| Client | Priority ceiling | Max concurrent | Notes |
|--------|-----------------|---------------|-------|
| graphiti | low | 2 | Background knowledge graph ingestion |
| jobsearch-mcp | low | 2 | bge-m3 embeddings for semantic job matching |
| searxng-mcp | normal | 4 | qwen3 query expansion + summarization |
| memsearch-watch | low | 2 | Via injection port 11436 — no Bearer needed |
| open-webui | normal | 8 | Key provisioned; not yet migrated to proxy |
| librechat | normal | 8 | Key provisioned; not yet migrated to proxy |
| admin | high | 0 (unlimited) | Management key — queue pause/resume/drain |

Consumers pass their key as `Authorization: Bearer <key>`. memsearch-watch uses the injection port at 11436 — requests arrive with no auth header and the proxy injects the `memsearch-watch` identity automatically.

## Routing

Model-aware routing across Ollama hosts. A background poller hits `GET /api/tags` on each host every 30 seconds, maintaining a live `(host → loaded_models)` map. Requests with a `model` field are routed to the host that already has it loaded — avoiding cold-start latency from model eviction.

```yaml
routing:
  strategy: model_aware
  fallback: any_healthy
```

When no host has the requested model, the proxy falls back to any healthy host. Fast-path invalidation: a 404 "model not found" response immediately removes that `(host, model)` pair from the routing table without waiting for the next poll.

## Features

### Priority queuing

Three tiers — `high`, `normal`, `low` — drained in order. Workers dispatch high before normal before low. Per-tier depth limits and expiry prevent queue overflow from building up unbounded.

A key's `max_priority` is enforced silently: a batch client configured with `max_priority: low` that sends `X-Queue-Priority: high` is capped to `low`.

### Embedding cache

Valkey-backed SHA256-keyed cache for `/api/embed` and `/api/embeddings`. Repeated RAG and semantic search requests skip the queue and upstream entirely. Cache TTL: 24 hours.

Cache key: SHA256 of `model + \0 + canonical_json(input)`, truncated to 32 hex chars. Per-endpoint namespacing prevents cross-endpoint collisions.

Metrics: `oqp_embedding_cache_hits_total`, `oqp_embedding_cache_misses_total`, `oqp_embedding_cache_errors_total` (labeled by client, model, endpoint).

### Client injection

Clients that can't send a Bearer header (memsearch-watch is a community tool with no auth support) use an injection port. Requests arrive at `127.0.0.1:11436` with no `Authorization` header; the proxy fills in the `memsearch-watch` identity and routes through the same queue with the same priority ceiling.

```yaml
client_injection:
  listeners:
    - listen_port: 11436
      inject_as: memsearch-watch
      bind: 127.0.0.1
  allow_public_injection: false
```

Injection ports default to loopback only. Binding to a non-loopback address requires `allow_public_injection: true` and emits a startup security warning when auth is also disabled.

### keep_alive injection

Default `keep_alive: 5m` is injected into all Ollama request bodies when the client doesn't set it. Prevents model eviction from GPU memory between bursty requests — a 20-second gap between embedding calls no longer triggers a 30-second model reload.

### Per-client concurrency caps

Each client has a `max_concurrent` asyncio semaphore. Background clients (graphiti, jobsearch-mcp, memsearch-watch) are capped at 2 in-flight requests. A batch job hitting its cap queues at the semaphore level — it can't monopolize worker slots to the detriment of interactive clients.

## Consumer Migration Status

| Consumer | Status | Priority | Notes |
|----------|--------|---------|-------|
| graphiti | ✅ Migrated | low | Background KG ingestion |
| jobsearch-mcp | ✅ Migrated | low | bge-m3 embeddings |
| searxng-mcp | ✅ Migrated | normal | qwen3 expand + summarize |
| memsearch-watch | ✅ Migrated | low | Injection port 11436 (no Bearer support upstream) |
| LibreChat | ⏳ Deferred | normal | Key provisioned; config change pending |
| Open WebUI | ⏳ Deferred | normal | Key provisioned; config change pending |

## Queue Visibility

Every response includes:

| Header | Value |
|--------|-------|
| `X-Queue-Wait-Time` | Milliseconds spent in queue |
| `X-Queue-Position` | Position at enqueue (omitted if dispatched immediately) |
| `X-Failover-Host` | Ollama host name that handled the request |
| `X-Cache` | `HIT` when served from embedding cache |
| `Retry-After` | Seconds on 503/429 queue overflow |

`GET /queue/status` — full queue state, host health, per-client stats, routing decisions.

`GET /metrics` — Prometheus text format. Key v0.2.0 metrics include `oqp_routing_decisions_total{reason}`, `oqp_host_models_loaded{host}`, `oqp_client_inflight{client_id}`, and `oqp_client_cap_waiting{client_id}`.

## Bugs Fixed During Initial Deployment

Two bugs found and fixed in the proxy source during the v0.1.x deployment phase:

1. **Streaming detection** — `application/x-ndjson` content-type was not recognized as a streaming response; the proxy was buffering responses that should stream. Fixed in v0.1.2.
2. **Webhook SSRF allowlist** — The internal ntfy hostname resolved to a LAN IP, which the SSRF check (designed to block internal IPs) rejected. Fixed by adding explicit hostname allowlisting alongside IP-range allowlisting.

Both fixes shipped in v0.1.2 and are included in v0.2.0.

## Full Reference

[TadMSTR/ollama-queue-proxy](https://github.com/TadMSTR/ollama-queue-proxy) — quick start, full config reference, migration guide (v0.1.x → v0.2.0), integration surface, webhook events, and management API.
