# Graphiti

Graphiti is forge's temporal knowledge graph — a Neo4j-backed system that stores
entity relationships with temporal metadata (when facts were true, when they changed).
Agents use it to record and query infrastructure state, decisions, and inter-entity
relationships that don't fit naturally in flat memory notes.

- **Compose:** `~/docker/graphiti/docker-compose.yml`
- **Appdata:** `/opt/appdata/graphiti/`
- **MCP endpoint:** `http://localhost:8000/mcp`

## Stack

| Container | Image | Purpose |
|-----------|-------|---------|
| `neo4j` | `neo4j:5.26.23` | Graph database |
| `graphiti-mcp` | `graphiti-mcp:local` (local build) | FastMCP HTTP server |

Neo4j ports `7474` (HTTP browser) and `7687` (Bolt) are localhost-only. The graphiti-mcp
HTTP endpoint at `8000` is also localhost-only — it is not SWAG-proxied.

Both containers are on `graphiti-internal` (isolated bridge) + `forge-net`. Neo4j is
only reachable from graphiti-mcp via the internal network.

## graphiti-mcp Configuration

Config at `~/docker/graphiti/config.yaml`:

```yaml
server:
  transport: http
  host: 0.0.0.0
  port: 8000

llm:
  provider: anthropic
  model: claude-sonnet-4-6-20250514

embedder:
  provider: openai          # OpenAI-compatible API
  model: bge-m3
  dimensions: 1024
  api_url: http://host.docker.internal:11435/v1  # ollama-queue-proxy
```

- **LLM:** Claude Sonnet 4.6 (entity extraction, deduplication)
- **Embeddings:** BGE-M3 via the local Ollama queue proxy (port 11435) at 1024 dimensions — no external API calls
- **Group ID:** `helm` (all forge agent episodes share this group)
- **Semaphore limit:** 5 concurrent operations

## Local Build Note

`graphiti-mcp` is built from a local `Dockerfile` in `~/docker/graphiti/` rather than
pulling a prebuilt image. This pins a specific graphiti-core version with a CVE fix
(CVE-2026-32247). The image is tagged `graphiti-mcp:local`. To rebuild after an upstream
change:

```bash
cd ~/docker/graphiti && docker compose build && docker compose up -d graphiti-mcp
```

## Memory Hierarchy

Graphiti supplements file-based memory (working memory, session notes) for relational
queries: "what connects to SWAG?", "what runs on which host?", "when did this decision
change?". It is not a replacement for flat notes — use both.

Graph contents are populated incrementally by memory-flush skill executions and by the
`graphiti-ingest` daily batch job (see below). Direct `add_memory` calls are used for
infrastructure state change events (deploys, service adds/removes, topology changes).

## Phase 4 Activation (2026-07-25) — `graphiti-ingest`

As part of Graphiti activation Phase 4, batch ingestion moved out of memory-sync
entirely and into its own dedicated job:

- **`graphiti-ingest`** — runs nightly at 05:00 via **system crontab** (not PM2, per the
  `pm2-cron-to-crontab-migration` convention), wrapped by `run-graphiti-ingest.sh`, using
  the venv at `/opt/venvs/graphiti-ingest`. It reuses the same `bge-m3` embedder
  configuration as graphiti-mcp rather than standing up a second embedding path.
- **memory-sync Step 5b** (the old weekly Graphiti batch-ingestion step, content-hash
  manifest at `graph-ingested.json`) was retired the same day to a **read-only freshness
  check**: it now only alerts if the newest ledger entry in `graph-ingested.json` is more
  than 48 hours old, rather than performing ingestion itself.

Audited under `graphiti-activation-2026-07`; one open finding (`OV-18`) in
`graphiti-ingest.py` — an unhandled `ValueError` in `canonical_key()` can bypass the
job's `#alerts` failure-notification contract, so a canonicalization bug could fail
silently rather than paging. Check `run-graphiti-ingest.sh` logs directly if the
freshness check hasn't fired but ingestion seems stale.

## Related Docs

- [memory-architecture.md](memory-architecture.md) — full system map showing how Graphiti relates to the note and index layers
- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch for vector/full-text search
- [nats.md](../agent/nats.md) — event bus (separate from graph storage)
