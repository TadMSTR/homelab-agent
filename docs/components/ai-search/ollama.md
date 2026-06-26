# Ollama

Ollama provides GPU-accelerated LLM inference on forge. It runs on the RTX 2000 Ada via the NVIDIA Container Toolkit and is proxied through SWAG with a split-auth model: the web UI requires Authentik login, the `/api` path is open for programmatic access (rate-limited, destructive endpoints blocked).

## Stack

| Setting | Value |
|---------|-------|
| Image | `ollama/ollama:latest` (floating — pin on next intentional update) |
| Container | `ollama` |
| Port | `127.0.0.1:11434` → container 11434 (localhost-bound on host) |
| Appdata | `/opt/appdata/ollama` (`/root/.ollama` inside container) |
| Network | `forge-net` |
| Runtime | `nvidia` (NVIDIA Container Toolkit) |
| Compose | `~/docker/ollama/docker-compose.yml` |

`OLLAMA_HOST=0.0.0.0` is required so SWAG can reach Ollama by container name (`ollama:11434`) via forge-net Docker DNS. Setting it to `127.0.0.1` would break the proxy.

## GPU

RTX 2000 Ada (16 GB VRAM). All model layers offloaded to GPU. The NVIDIA Container Toolkit is installed on the forge host; `runtime: nvidia` in the compose file grants the container GPU access.

**Note:** Secure Boot is disabled on forge — required for NVIDIA DKMS open kernel modules. This is an accepted, documented risk for this host.

## Models

| Model | Size | Purpose |
|-------|------|---------|
| `qwen3:14b` | 9.3 GB | Primary inference — fits in VRAM |
| `qwen3:4b` | 2.5 GB | Fast/lightweight, lower context cost |
| `nomic-embed-text:latest` | 274 MB | Embeddings |

Models stored at `/opt/appdata/ollama/models/`.

## SWAG Proxy

`ollama.subdomain.conf` implements a split-auth model:

| Path | Auth | Notes |
|------|------|-------|
| `/` | Authentik forward auth | Web UI — full model management |
| `/api` | None (open) | Programmatic access — rate-limited |
| `/api/(delete\|pull\|push\|copy)` | Blocked (403) | Destructive endpoints — blocked regardless |

Rate limit on `/api`: `10r/s burst=30` (zone defined in `site-confs/rate-limit-zones.conf`). Body size cap on `/api`: 10 MB. Server-level `client_max_body_size 0` is intentional for the authenticated root path (model downloads via UI are large).

**Why `/api` is open:** MCP tools and agent scripts need direct API access without a browser auth flow. Destructive endpoints (pull/delete/push) are blocked at the nginx layer — these require authenticated access via the root `/` path.

## API Usage

```bash
# Generate (via SWAG proxy)
curl https://ollama.helmforge.me/api/generate \
  -d '{"model":"qwen3:4b","prompt":"hello","stream":false}'

# From forge host directly (no auth needed)
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen3:4b","prompt":"hello","stream":false}'

# Embeddings
curl http://localhost:11434/api/embed \
  -d '{"model":"nomic-embed-text","input":"some text"}'
```

## Model Management

Destructive operations (pull/delete) must go through the authenticated root path or directly from the forge host:

```bash
# From forge host — direct API, no proxy
docker exec ollama ollama pull qwen3:14b
docker exec ollama ollama list
docker exec ollama ollama rm <model>
```

## Security Notes

From the Phase 7 GPU build security audit:
- **H1 (fixed):** Destructive endpoints (`/api/delete|pull|push|copy`) now return 403 unconditionally
- **M1 (fixed):** Docker daemon metrics moved from `0.0.0.0:9323` to `127.0.0.1:9323`
- **M2 (fixed):** `client_max_body_size 10m` + rate limiting added to `/api` location
- **L2 (accepted):** `OLLAMA_HOST=0.0.0.0` means any forge-net container can reach Ollama directly bypassing auth — accepted as Ted controls forge-net membership
- **L1 (deferred):** Image tag not yet pinned — pin on next intentional update

## Related Docs

- [nvidia-exporter.md](../observability/nvidia-exporter.md) — GPU metrics
- [authentik.md](../foundation/authentik.md) — forward auth configuration
- [swag.md](../foundation/swag.md) — SWAG proxy and auth model
- [phase-7-agent-infrastructure.md](../../phases/phase-7-agent-infrastructure.md) — Phase 7 context (same build)
