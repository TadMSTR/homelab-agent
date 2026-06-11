# Memory Stack

The memory stack provides the vector and full-text search backends that power forge's
agent memory system. It runs two storage engines on an isolated `memory-net` bridge
network: Milvus (vector search) and OpenSearch (full-text search).

- **Compose:** `~/docker/memory-stack/docker-compose.yml`
- **Appdata:** `/opt/appdata/memory-stack/`
- **Network:** `memory-net` (isolated — no `forge-net` membership)

## Containers

| Container | Image | Purpose |
|-----------|-------|---------|
| `milvus` | `milvusdb/milvus:v2.5.27` | Vector similarity search |
| `milvus-etcd` | `quay.io/coreos/etcd:v3.5.5` | Milvus cluster metadata store |
| `milvus-minio` | `minio/minio:RELEASE.2023-03-13T19-46-17Z` | Milvus segment object storage |
| `opensearch` | `opensearchproject/opensearch:2.17.0` | Full-text search (BM25 + hybrid) |

## Access

Both services listen on localhost-only ports — not accessible from the LAN:

| Service | Port | Consumer |
|---------|------|----------|
| Milvus gRPC/HTTP | `127.0.0.1:19530` | `memsearch-watch`, `qmd` |
| OpenSearch REST | `127.0.0.1:9202` | `memory-search-mcp` |

OpenSearch security plugin is disabled (`DISABLE_SECURITY_PLUGIN=true`). The
localhost-only port binding is the access control boundary — no external exposure.
The port is `9202` (not the default `9200`) to avoid conflict with any future
OpenSearch instance on the same host.

## Milvus Architecture

Milvus standalone mode: a single `milvus` process backed by etcd (cluster metadata)
and MinIO (segment files). All three containers must be healthy before Milvus starts.
Data at `/opt/appdata/memory-stack/milvus/`.

## Consumers

| PM2 service | What it indexes | Backend |
|-------------|----------------|---------|
| `memsearch-watch` | `~/.claude/memory/` (watched, debounced) | Milvus |
| `qmd` | 8 000+ markdown docs across all collections | Milvus |
| `memory-search-mcp` | Memory notes full-text | OpenSearch |
| `memory-metadata-mcp` | Memory note metadata (SQLite) | — (local file) |

See [memory-services.md](memory-services.md) for the PM2 layer on top of this stack.

## Related Docs

- [memory-services.md](memory-services.md) — PM2 MCP services that sit on top of this stack
- [graphiti.md](graphiti.md) — separate knowledge graph backend (Neo4j)
