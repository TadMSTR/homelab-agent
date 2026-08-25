# Graphiti (retired 2026-08-05)

Graphiti was forge's temporal knowledge graph — a Neo4j-backed system that stored entity
relationships with temporal metadata (when facts were true, when they changed). Agents used
it to record and query infrastructure state, decisions, and inter-entity relationships that
didn't fit naturally in flat memory notes.

## Retirement

Ted shut the stack off 2026-08-04 after it hit the Anthropic API hard enough to lock the API
billing account. Decommissioned under vikunja#345 (id 364, `graphiti-decommission-2026-08`) in
a 3-phase handoff: sysadmin removed it from scoped-mcp manifests and stopped the affected
processes (urgent, same day), developer updated the CloudCLI dashboard client, and this doc
sweep is the writer phase. The `graphiti-ingest` nightly cron and the `memory-sync` freshness
check that watched it were both disabled as part of the same decommission.

The compose stack (`~/docker/graphiti/docker-compose.yml`), appdata (`/opt/appdata/graphiti/`),
and the `graphiti-mcp` HTTP endpoint no longer exist — `docker ps -a --filter name=graphiti`
returns nothing, not even stopped containers.

There is no replacement relational/temporal layer. Agents fall back to flat memory notes
(session/working/distilled tiers) for the queries Graphiti used to answer — see
[memory-architecture.md](memory-architecture.md).

## What it was

- **Compose:** `~/docker/graphiti/docker-compose.yml` (neo4j + graphiti-mcp, `graphiti-internal`
  isolated network + `forge-net`)
- **MCP endpoint:** `http://localhost:8000/mcp`, localhost-only, not SWAG-proxied
- **LLM:** Claude Sonnet 4.6 for entity extraction/deduplication
- **Embeddings:** BGE-M3 via the local Ollama queue proxy, 1024 dimensions
- **Group ID:** `helm` (all forge agent episodes shared this group)
- Local-built image (`graphiti-mcp:local`) to pin a graphiti-core version with a CVE fix
  (CVE-2026-32247)

## Related Docs

- [memory-architecture.md](memory-architecture.md) — current memory system map (no graph layer)
- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch for vector/full-text search
