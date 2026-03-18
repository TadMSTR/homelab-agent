# Graphiti Knowledge Graph

Graphiti is a temporal knowledge graph backed by Neo4j. It gives agents a way to query relationships between infrastructure entities — services, hosts, networks, agents, configurations — rather than searching flat text. When an agent asks "what connects to SWAG?" or "what runs on atlas?", Graphiti returns structured relationships with temporal metadata, not keyword-matched document fragments.

It sits alongside the file-based memory system as a complementary query surface. File-based memory is better for historical decisions and context narratives. The knowledge graph is better for topology, relationships, and "what connects to what" questions.

## Why a Knowledge Graph

The file-based memory system (memsearch + memory-sync + qmd) handles narrative knowledge well — decisions, rationale, session context. But it's poor at relational queries. If you want to know which services depend on the SWAG reverse proxy, you'd need to grep across multiple docs and mentally assemble the relationships. That's exactly what a graph database is built for.

Graphiti adds a structured layer where entities (services, hosts, ports) are nodes and their relationships are edges with temporal validity. When infrastructure changes — a service moves hosts, a port remapping happens, a new agent is added — the graph captures both the new state and when the change occurred. Old facts aren't deleted; they're superseded. You can query current state or trace how the topology evolved.

The graph is populated automatically. The memory-flush skill feeds it in real-time during interactive sessions. The nightly memory-sync pipeline batch-ingests notes via Step 5b. Agents don't need to think about graph maintenance — they just use `search_memory_facts` and `search_nodes` when they need relational answers.

## How It Works

Two containers, network-isolated from the main stack:

**Neo4j 5.26.0** — the graph database. Stores nodes (entities) and edges (relationships) with properties and temporal metadata. Exposes the browser UI on port 7474 (proxied at `neo4j.yourdomain` behind Authelia) and Bolt protocol on 7687 for programmatic access. Sits on both `claudebox-net` (for SWAG proxy access) and a dedicated `graphiti-internal` network.

**Graphiti MCP** — an MCP server that wraps the Graphiti library. Accepts episodes (text content), uses an LLM to extract entities and relationships, generates embeddings for semantic search, and writes everything to Neo4j. Exposes MCP tools over HTTP on port 8000. Sits on `graphiti-internal` only — deliberately isolated from `claudebox-net`. Agents access it directly via `localhost:8000` on the host, not through the Docker network.

The extraction pipeline for each ingested episode:
1. LLM (Claude Sonnet) reads the text and identifies entities matching the prescribed ontology
2. LLM extracts relationships between entities with temporal context
3. Embeddings (Voyage AI voyage-3-lite, 512 dimensions) are generated for semantic similarity search
4. Entities are resolved against existing graph nodes (deduplication)
5. New nodes and edges are written to Neo4j; superseded facts get invalidation timestamps

### Entity Ontology

The graph uses a prescribed set of entity types configured in `config.yaml`:

| Type | Description |
|------|-------------|
| Service | A running service, container, or application |
| Host | A physical or virtual machine |
| Network | A network, subnet, VLAN, or Docker network |
| Configuration | A configuration file, setting, or parameter |
| Agent | A Claude Code agent or automated process |
| User | A human user or account |
| Port | A network port or port mapping |

This ontology constrains entity extraction so the graph stays focused on infrastructure topology rather than trying to model everything.

## Configuration

**Docker Compose:** The stack uses a custom Dockerfile that extends `zepai/knowledge-graph-mcp:1.0.2-standalone` to install the `anthropic` and `voyageai` Python packages (not bundled in the base image).

**Config file (`config.yaml`):**

Key settings:
- `llm.provider: anthropic` with `model: claude-sonnet-4-6` — used for entity extraction
- `embedder.provider: voyage` with `model: voyage-3-lite` (512 dimensions) — used for semantic search
- `graphiti.entity_types` — the prescribed ontology (see above)
- `graphiti.group_id: homelab` — all data lives under this group

**Environment variables** (in `.env`):
- `NEO4J_PASSWORD` — Neo4j auth
- `ANTHROPIC_API_KEY` — for entity extraction LLM calls
- `VOYAGE_API_KEY` — for embedding generation
- `OPENAI_API_KEY=unused` — required by the base image init code even when not using OpenAI

**SWAG proxy:** Neo4j browser proxied behind Authelia for manual graph inspection. The Graphiti MCP endpoint at `localhost:8000` is not proxied — it's accessed directly by agents on the host.

## Prerequisites

- Docker CE + Compose
- An Anthropic API key (entity extraction uses Claude Sonnet)
- A Voyage AI API key (embeddings)
- SWAG + Authelia (optional, for Neo4j browser access)

## Data Flow

```
Interactive sessions ──→ memory-flush skill ──→ Graphiti MCP ──→ Neo4j
                                                     ↑
Nightly memory-sync ──→ Step 5b (batch ingest) ──────┘
                         (content hash manifest
                          for deduplication)

Agent queries ──→ search_memory_facts / search_nodes ──→ Neo4j
```

**Real-time ingestion:** The `memory-flush` skill calls `add_memory` during interactive sessions for infrastructure state changes — deploys, service adds/removes, network changes, port remaps.

**Batch ingestion:** Memory-sync Step 5b runs nightly after distillation. It ingests notes that were created, updated, or changed since the last run, using a content hash manifest (`~/.claude/memory/graph-ingested.json`) to avoid duplicate ingestion.

**Querying:** Agents use `search_memory_facts` for relationship queries ("what depends on SWAG?") and `search_nodes` for entity lookups ("tell me about the grafana stack"). Results include temporal metadata so agents can distinguish current state from historical.

## Integration Points

**Memory-sync pipeline:** Step 5b ingests working and distilled notes after the main distillation steps. Uses a content hash manifest for idempotency. If Graphiti is unavailable, the step logs the failure and continues — it doesn't block the rest of the pipeline.

**memory-flush skill:** Real-time graph feeding during interactive sessions. Agents call `add_memory` for infrastructure events that should be immediately queryable rather than waiting for the nightly batch.

**CLAUDE.md instructions:** The root CLAUDE.md directs agents to prefer the graph for topology/relationship queries and file-based memory for historical decisions. Both systems are consulted; the graph supplements rather than replaces file-based memory.

**Neo4j browser:** Available via SWAG for manual inspection of the graph. Useful for verifying entity resolution quality and checking that the ontology is working as expected.

## Gotchas and Lessons Learned

**`OPENAI_API_KEY=unused` is required.** The base Graphiti image expects this environment variable during initialization, even when using Anthropic and Voyage AI exclusively. Set it to any non-empty string in `.env` to prevent the init error.

**Temperature must be explicit.** The config file must set `llm.temperature: 1.0` explicitly. Without it, the Anthropic client may use defaults that produce inconsistent entity extraction.

**Custom Dockerfile for provider packages.** The `zepai/knowledge-graph-mcp:1.0.2-standalone` image bundles OpenAI support but not Anthropic or Voyage AI. The custom Dockerfile runs `pip install anthropic voyageai` into the app's virtualenv. When upgrading the base image, verify the Dockerfile still targets the correct Python path.

**Entity resolution is imperfect.** The LLM-based entity extraction occasionally creates duplicate nodes for the same entity (e.g., "grafana" and "Grafana" as separate nodes). Graphiti's built-in entity resolution catches most of these, but some slip through. Periodic manual review via the Neo4j browser helps. The prescribed ontology reduces but doesn't eliminate this.

**The graph is being populated incrementally.** If a query returns no results, fall back to file-based memory. The graph gets richer over time as more episodes are ingested through memory-sync runs and interactive memory-flush calls.

**API costs.** Each ingested episode triggers LLM calls (entity extraction) and embedding API calls. Memory-sync batches are modest (typically <20 notes per run), but be aware of the per-episode cost if you're bulk-ingesting a large backlog.

**Neo4j memory tuning.** The compose file allocates 512MB heap + 512MB page cache + 1GB max heap. This is conservative for a homelab graph that won't grow to millions of nodes. Adjust `NEO4J_server_memory_*` environment variables if you see memory pressure or if the graph grows significantly.

## Standalone Value

Graphiti requires the memory system to be useful — without memory-sync and memory-flush feeding it, the graph stays empty. It's an enhancement to the existing Layer 3 memory pipeline, not a standalone component. But within that context, it adds a query capability that flat-file memory can't provide: structured relationship traversal across infrastructure entities with temporal awareness.

If you're adopting the memory system from this repo, add Graphiti after you have memory-sync running reliably. The graph needs a steady feed of content to be useful, and memory-sync is what provides that feed.

## Further Reading

- [Graphiti GitHub](https://github.com/getzep/graphiti) — the library and MCP server
- [Neo4j documentation](https://neo4j.com/docs/)
- [Voyage AI](https://www.voyageai.com/) — embedding provider

---

## Related Docs

- [Architecture overview](../../README.md#the-memory--context-system) — the memory system context
- [memory-sync](memory-sync.md) — nightly batch ingestion via Step 5b
- [memsearch](memsearch.md) — complementary session-level memory recall
- [qmd](qmd.md) — complementary semantic search over broader document collections
- [CLAUDE.md examples](../../claude-code/) — agent project configs referencing the knowledge graph
