# Memory Stack

The memory stack runs two storage engines on an isolated `memory-net` bridge network:
Milvus (vector search) and OpenSearch (full-text search). **Milvus was stopped 2026-09-17**
as part of the memsearch retirement — see below. OpenSearch is still live and backs
`memory-fulltext-mcp`.

- **Compose:** `~/docker/memory-stack/docker-compose.yml`
- **Appdata:** `/opt/appdata/memory-stack/`
- **Network:** `memory-net` (isolated — no `forge-net` membership)

## Containers

| Container | Image | Status | Purpose |
|-----------|-------|--------|---------|
| `milvus` | `milvusdb/milvus:v2.5.27` | **Stopped** (`Exited (0)`, since 2026-09-17) | Vector similarity search — no consumer remains |
| `milvus-etcd` | `quay.io/coreos/etcd:v3.5.5` | **Stopped** | Milvus cluster metadata store |
| `milvus-minio` | `minio/minio:RELEASE.2023-03-13T19-46-17Z` | **Stopped** | Milvus segment object storage |
| `opensearch` | `opensearchproject/opensearch:2.17.0` | Running | Full-text search (BM25 + hybrid) |

## Milvus retirement

Stopped, not removed — `docker compose stop`, not `down -v`. Data deliberately preserved:
`/opt/appdata/memsearch/` (11 GB) and the `milvus-minio` volume are both intact, so
restarting the stack is a `docker compose up -d` away, not a re-embed from scratch. See
[memsearch.md](memsearch.md#retirement) for the full retirement record
(`memory-consolidation-2026-09` part 3, vikunja#863). Its only consumers —
`memsearch-watch-fast`, `memsearch-watch-templates`, and `qmd`'s (never-used) Milvus
backend option — are gone or were never wired to it; qmd uses its own in-process
`llama.cpp` embedder and GGUF models, not Milvus.

## Access

| Service | Port | Consumer |
|---------|------|----------|
| Milvus gRPC/HTTP | `127.0.0.1:19530` | None — stopped, port free |
| OpenSearch REST | `127.0.0.1:9202` | `memory-fulltext-mcp` |

OpenSearch security plugin is disabled (`DISABLE_SECURITY_PLUGIN=true`). The
localhost-only port binding is the access control boundary — no external exposure.
The port is `9202` (not the default `9200`) to avoid conflict with any future
OpenSearch instance on the same host.

## Consumers

| PM2 service | What it indexes | Backend |
|-------------|----------------|---------|
| `memory-fulltext-mcp` | Memory notes full-text | OpenSearch |
| `memory-metadata-mcp` | Memory note metadata (SQLite) | — (local file) |
| `qmd` | 9 000+ markdown docs across all collections | Own in-process `llama.cpp` embedder — not Milvus |

See [memory-services.md](memory-services.md) for the PM2 layer on top of this stack.

## Related Docs

- [memory-services.md](memory-services.md) — PM2 MCP services that sit on top of this stack
- [memsearch.md](memsearch.md) — the retired Milvus consumer, full cutover record
- [graphiti.md](graphiti.md) — knowledge graph backend (Neo4j), retired 2026-08-05
