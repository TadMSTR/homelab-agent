# graphiti-mcp

The `graphiti-mcp` container is the MCP server component of the Graphiti knowledge graph stack. It runs the Graphiti library as a Streamable HTTP MCP server, exposing tools for adding episodes and querying nodes and facts in the Neo4j graph.

See **[graphiti.md](graphiti.md)** for full documentation — architecture, configuration, entity ontology, ingestion pipeline, and integration points.

## Quick Reference

- **Container:** `graphiti-mcp` (custom image: `graphiti-mcp:local`)
- **Transport:** Streamable HTTP on `localhost:8000`
- **Network:** `graphiti-internal` only — not on `claudebox-net`
- **Access:** Agents connect directly via `localhost:8000` on the host (not through Docker networking)
- **MCP tools:** `add_memory`, `search_memory_facts`, `search_nodes`, `get_episodes`, `get_entity_edge`, `delete_entity_edge`, `delete_episode`, `get_status`, `clear_graph`
