# milvus

Milvus standalone is the vector database that backs [memsearch](memsearch.md). It stores the embedding vectors generated from agent memory files and responds to similarity queries — every `memsearch search` call hits it. The database runs as a Docker container on localhost with embedded etcd, requiring no external coordination service.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) as a foundational dependency: memsearch won't start without it, and without memsearch the automatic memory injection that carries context between sessions stops working.

## Why Milvus

memsearch needs a vector store that handles:

- High-dimensional float vectors (1024-dim for bge-m3)
- Collection-level CRUD (insert, delete, search by cosine similarity)
- Reliable persistence across restarts

SQLite-backed stores (e.g. sqlite-vec, chroma with sqlite backend) were tested early in the stack and rejected — they either had poor performance at ~5k documents or lacked the range deletion needed for memory compaction. Milvus standalone with embedded etcd provides production-grade vector search while still being a single Docker container with no external dependencies.

## How It Works

```
memsearch CLI / memsearch-watch
  │
  └─ connects to localhost:19530
       │
       └─ Milvus standalone
            ├─ collection: memsearch_chunks
            │    ├─ 1024-dim bge-m3 vectors
            │    └─ metadata: path, tier, created, tags, body excerpt
            │
            └─ embedded etcd (state storage, single-node)
                 └─ data at /var/lib/milvus/etcd
```

memsearch writes to the `memsearch_chunks` collection during index runs and deletes entries by source path during reindexing. It queries by vector similarity (cosine) at search time, filtered by metadata fields like `tier` or file path prefix. The database is derived — the markdown files in `~/.claude/memory/` are the source of truth; the Milvus collection can always be rebuilt from them.

## Compose Configuration

```yaml
services:
  milvus:
    image: milvusdb/milvus:v2.6.17
    container_name: milvus
    command: milvus run standalone
    security_opt:
      - seccomp:unconfined  # embedded etcd uses clone syscall flags blocked by default Docker seccomp profile
    environment:
      DEPLOY_MODE: "standalone"       # required in v2.6+; see Upgrade Notes below
      ETCD_USE_EMBED: "true"
      ETCD_DATA_DIR: /var/lib/milvus/etcd
      ETCD_CONFIG_PATH: /milvus/configs/embedEtcd.yaml
      COMMON_STORAGETYPE: local
    volumes:
      - /opt/appdata/milvus:/var/lib/milvus
      - ./embedEtcd.yaml:/milvus/configs/embedEtcd.yaml:ro
    ports:
      - "127.0.0.1:19530:19530"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:9091/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s    # v2.6 MixCoord takes longer to initialize than v2.5 standalone
    mem_limit: 3g
    cpus: '2.0'
    restart: unless-stopped
```

The `embedEtcd.yaml` config alongside the compose file binds etcd listeners on `0.0.0.0` within the container and sets the data directory. Both files are required — Milvus panics at startup if the etcd config path is missing.

## Upgrade Notes

### v2.5 → v2.6

**`DEPLOY_MODE: standalone` is required.** Milvus v2.6 refactored coordinator services into a unified `MixCoord` process. As part of this change, `EtcdConfig.Init` now reads `DEPLOY_MODE` explicitly to determine startup behavior — and panics if the variable is absent, even when embedded etcd is configured and no external coordinators are involved. Add this env var before upgrading; the container will not start without it.

The embedded etcd setup, local storage, and port bindings are otherwise unchanged from v2.5.

**`start_period` increase.** MixCoord initialization in v2.6 takes longer than the previous standalone coordinator startup. Healthcheck `start_period` should be at least 90s; 60s (sufficient for v2.5) will cause the container to be flagged unhealthy before it's ready.

**Backup before upgrading.** The etcd WAL files in `/opt/appdata/milvus/etcd` are root-owned (written by etcd running as root inside the container). A full backup requires `sudo` for the etcd subdirectory. Back up the entire `/opt/appdata/milvus` volume before starting the upgrade, then verify the container health endpoint is responding before declaring success.

## Operations

**Normal restart** (settings change, host reboot):
```bash
docker compose -f ~/docker/milvus/docker-compose.yml restart milvus
```

**Rebuild the index** (after a Milvus upgrade, or if the collection is corrupt):
```bash
# Stop memsearch-watch first so it doesn't race with the rebuild
pm2 stop memsearch-watch

# Wipe and restart Milvus
docker compose -f ~/docker/milvus/docker-compose.yml down
sudo rm -rf /opt/appdata/milvus/*
docker compose -f ~/docker/milvus/docker-compose.yml up -d

# Wait for healthy, then rebuild
docker inspect milvus | grep Health
OLLAMA_HOST=http://127.0.0.1:11435 memsearch index

pm2 start memsearch-watch
```

**Health check:**
```bash
curl -s http://localhost:9091/healthz
```

Port 9091 (metrics/health) is not published to the host — the healthcheck hits it container-internally. Do not expose this port; the LibreChat metrics exporter uses the same host port.

## Gotchas

**`DEPLOY_MODE` must be set.** Omitting it causes a panic in v2.6+. The error appears in `docker logs milvus` as a nil pointer dereference inside `EtcdConfig.Init` — not an obvious config error. Add `DEPLOY_MODE: "standalone"` to the environment block if upgrading from v2.5.

**`seccomp:unconfined` is required.** The embedded etcd process uses `CLONE_NEWUSER` and related syscall flags that Docker's default seccomp profile blocks. Without this, the container starts but etcd fails silently, and Milvus eventually times out waiting for etcd to become ready.

**The database is rebuilable.** If the Milvus collection gets corrupted or the index diverges from the source files, wipe the data volume and run `memsearch index` — the markdown files are the source of truth. Expect a full re-index to take 5–10 minutes depending on collection size and Ollama GPU throughput.

**Dimension mismatches prevent indexing.** Changing the embedding model changes the vector dimension. The existing collection cannot store vectors of a different dimension — it will fail with a schema mismatch error. Any embedding model change requires a full collection wipe and re-index (same procedure as a corrupt-index rebuild).

## Related Docs

- [memsearch](memsearch.md) — the CLI tool and Claude Code plugin that read from and write to Milvus
- [memory-pipeline](memory-pipeline.md) — the nightly pipeline that triggers index updates
- [ollama-queue-proxy](ollama-queue-proxy.md) — the proxy memsearch routes embedding calls through
