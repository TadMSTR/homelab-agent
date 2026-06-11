# Reranker

Custom FlashRank reranker — a FastAPI service that scores and reorders search results by semantic relevance. Exposes a Jina-compatible `/v1/rerank` endpoint. Used by searxng-mcp as the final scoring step in the web search pipeline.

- **Port:** `8787` (forge-net internal)
- **Compose:** `~/docker/reranker/docker-compose.yml`
- **Dockerfile:** `~/docker/reranker/Dockerfile` (custom build)
- **Network:** `forge-net`
- **No SWAG proxy** — internal use only

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

Downloads a FlashRank ranking model (~100MB) on first container start. Subsequent starts use the cached model (persisted in container volume or appdata). Expect a 30–60s delay on cold start while the model loads.

## Usage in Search Pipeline

searxng-mcp calls the reranker after fetching and extracting page content:

```
SearXNG results → Firecrawl/Crawl4ai content extraction → Reranker → top-N results returned to agent
```

The reranker is the last step before results are returned. It improves result quality by scoring extracted content against the original query rather than relying solely on SearXNG's link-order ranking.

## Related Docs

- [phase-5-user-stack-infra.md](../../phases/phase-5-user-stack-infra.md) — web search pipeline architecture
- [firecrawl.md](firecrawl.md) — content extraction (feeds into reranker)
- [crawl4ai.md](crawl4ai.md) — browser-based extraction (feeds into reranker)
