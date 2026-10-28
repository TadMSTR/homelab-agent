# Reranker

Custom FlashRank reranker — a FastAPI service that scores and reorders search results by semantic relevance. Exposes a Jina-compatible `/v1/rerank` endpoint. Used by searxng-mcp as the final scoring step in the web search pipeline.

- **Image:** `ghcr.io/tadmstr/searxng-mcp-reranker`, published from the searxng-mcp repo and pinned by version and digest. The FlashRank model is baked into the image; it runs as UID 10001 with a read-only root filesystem, `cap_drop: ALL` and `no-new-privileges`
- **Compose:** the `reranker` service in `~/docker/searxng/docker-compose.yml`. It moved there on 2026-09-07 from its own `reranker` stack, so it sits next to searxng-mcp, its primary consumer. The old `~/docker/reranker/` directory and local `build: .` no longer exist
- **Model:** `RERANKER_MODEL=ms-marco-MiniLM-L-12-v2`
- **Port:** `8787` on `forge-net`, plus `127.0.0.1:8787` on the host (loopback only — the service has no authentication)
- **Network:** `forge-net`, reached by the service name `reranker`. There is deliberately no `container_name:` (a fixed name is global to the Docker host and once collided with another stack's container)
- **No SWAG proxy** — internal use only

## Consumers

- **searxng-mcp** — the final scoring step in the web search pipeline (below)
- **A chat UI (LibreChat)** — calls `http://reranker:8787/v1/rerank` directly through its
  Jina-compatible reranker setting. It has no reranker health surface of its own, so a broken
  `reranker` alias degrades it silently. Do not rename the service.

## API

Jina-compatible rerank endpoint:

```
POST http://reranker:8787/v1/rerank
Content-Type: application/json

{
  "model": "...",
  "query": "search query text",
  "documents": ["doc1 text", "doc2 text", ...]
}
```

Returns documents sorted by relevance score (descending).

## FlashRank Model

The FlashRank ranking model is baked into the published image, so there is no first-start download and no model cache to persist. (Before the 2026-09-07 cutover, a locally built image downloaded the model at runtime and ran as root.)

## Usage in Search Pipeline

searxng-mcp calls the reranker after fetching and extracting page content:

```
SearXNG results → Firecrawl/Crawl4ai content extraction → Reranker → top-N results returned to agent
```

The reranker is the last step before results are returned. It improves result quality by scoring extracted content against the original query rather than relying solely on SearXNG's link-order ranking.

## Related Docs

- [phase-5-user-stack-infra.md](../../phases/phase-5-user-stack-infra.md) — web search pipeline architecture
- [firecrawl-v2.md](firecrawl-v2.md) — content extraction (feeds into reranker)
- [crawl4ai.md](crawl4ai.md) — browser-based extraction (feeds into reranker)
- [searxng-mcp.md](searxng-mcp.md) — primary consumer; same compose stack
- [librechat.md](../apps/librechat.md) — second consumer
