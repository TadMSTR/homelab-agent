# Docker Compose Files

Sanitized Docker Compose files for every service in the Layer 2 stack. Each subdirectory contains a `docker-compose.yml` and any supporting config files needed to deploy that service.

All services share a single Docker bridge network. Secrets and environment-specific values use placeholder variables — copy `.env.example` to `.env` and fill in your values.

## Stacks

| Stack | Containers | Component Doc |
|-------|-----------|---------------|
| [authelia/](authelia/) | Authelia SSO gateway | [docs/components/authelia.md](../docs/components/authelia.md) |
| [blog-preview/](blog-preview/) | MkDocs Material preview server | [docs/components/blog-preview.md](../docs/components/blog-preview.md) |
| [crawl4ai/](crawl4ai/) | Crawl4AI web scraping API | [docs/components/crawl4ai.md](../docs/components/crawl4ai.md) |
| [dockhand/](dockhand/) | Dockhand Docker stack manager | [docs/components/dockhand.md](../docs/components/dockhand.md) |
| [firecrawl-simple/](firecrawl-simple/) | Firecrawl API, Puppeteer, Redis, worker | [docs/components/searxng.md](../docs/components/searxng.md) (§Web Search Pipeline) |
| [grafana/](grafana/) | InfluxDB 2.7, Grafana 11.6.0, Loki 3.6.8, image-renderer | [docs/components/grafana-claudebox.md](../docs/components/grafana-claudebox.md) |
| [graphiti/](graphiti/) | Neo4j 5.26.x, Graphiti MCP (custom build) | [docs/components/graphiti.md](../docs/components/graphiti.md) |
| [jobsearch/](jobsearch/) | jobsearch-mcp, job-watcher, Postgres, Qdrant, Valkey | [docs/components/jobsearch-mcp.md](../docs/components/jobsearch-mcp.md) |
| [librechat/](librechat/) | LibreChat, MongoDB, Meilisearch, LibreChat Exporter, optional MCP sidecars | [docs/components/librechat.md](../docs/components/librechat.md) |
| [milvus/](milvus/) | Milvus standalone v2.5.x (embedded etcd) | [docs/components/memsearch.md](../docs/components/memsearch.md) (§Vector Store) |
| [n8n/](n8n/) | n8n workflow engine, Postgres | [docs/components/n8n.md](../docs/components/n8n.md) |
| [nats/](nats/) | NATS 2.12.x with JetStream | [docs/components/nats-jetstream.md](../docs/components/nats-jetstream.md) |
| [ntfy-mcp/](ntfy-mcp/) | ntfy-mcp notification server | [mcp-servers/README.md](../mcp-servers/README.md#ntfy-mcp) |
| [plane/](plane/) | Plane project management (12 containers) | [docs/components/plane.md](../docs/components/plane.md) |
| [reranker/](reranker/) | FlashRank reranker (custom build) | [docs/components/searxng.md](../docs/components/searxng.md) (§Rerank) |
| [searxng/](searxng/) | SearXNG, Valkey | [docs/components/searxng.md](../docs/components/searxng.md) |
| [searxng-mcp-cache/](searxng-mcp-cache/) | Valkey cache for searxng-mcp | [docs/components/searxng-mcp.md](../docs/components/searxng-mcp.md) |
| [swag/](swag/) | SWAG reverse proxy | [docs/components/swag.md](../docs/components/swag.md) |
| [task-queue-mcp/](task-queue-mcp/) | Task queue MCP server (local build) | [docs/components/task-queue-mcp.md](../docs/components/task-queue-mcp.md) |
| [temporal/](temporal/) | Temporal server, UI, Postgres, admin-tools | [docs/components/temporal.md](../docs/components/temporal.md) |

## Deployment Order

SWAG → Authelia → everything else. See [Getting Started](../docs/getting-started.md) for the full dependency-ordered setup guide.

## Related Docs

- [Architecture — Network Topology](../docs/architecture.md#network-topology) — How containers connect
- [Backups](../docs/components/backups.md) — Docker appdata backup strategy
