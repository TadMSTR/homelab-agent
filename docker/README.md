# Docker Compose Files

Sanitized Docker Compose files for every service in the Layer 2 stack. Each subdirectory contains a `docker-compose.yml` and any supporting config files needed to deploy that service.

All services share a single Docker bridge network. Secrets and environment-specific values use placeholder variables — copy `.env.example` to `.env` and fill in your values.

## Stacks

| Stack | Containers | Component Doc |
|-------|-----------|---------------|
| [authelia/](authelia/) | Authelia SSO gateway | [docs/components/authelia.md](../docs/components/authelia.md) |
| [dockhand/](dockhand/) | Dockhand Docker stack manager | [docs/components/dockhand.md](../docs/components/dockhand.md) |
| [firecrawl-simple/](firecrawl-simple/) | Firecrawl API, Puppeteer, Redis, worker | [docs/components/librechat.md](../docs/components/librechat.md) (§Web Search Pipeline) |
| [librechat/](librechat/) | LibreChat, MongoDB, Meilisearch | [docs/components/librechat.md](../docs/components/librechat.md) |
| [open-notebook/](open-notebook/) | Open Notebook, SurrealDB | [docs/components/open-notebook.md](../docs/components/open-notebook.md) |
| [perplexica/](perplexica/) | Perplexica, SearXNG, Valkey | [docs/components/perplexica.md](../docs/components/perplexica.md) |
| [reranker/](reranker/) | FlashRank reranker (custom build) | [docs/components/librechat.md](../docs/components/librechat.md) (§Rerank) |
| [swag/](swag/) | SWAG reverse proxy | [docs/components/swag.md](../docs/components/swag.md) |

## Deployment Order

SWAG → Authelia → everything else. See [Getting Started](../docs/getting-started.md) for the full dependency-ordered setup guide.

## Related Docs

- [Architecture — Network Topology](../docs/architecture.md#network-topology) — How containers connect
- [Backups](../docs/components/backups.md) — Docker appdata backup strategy
