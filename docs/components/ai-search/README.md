# AI & Search — Inference, Web Search & Content Extraction

Local LLM inference, web search, and content extraction services. Ollama handles model serving on the NVIDIA GPU; SearXNG provides privacy-respecting web search; Firecrawl and Crawl4AI extract structured content from web pages.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [ollama.md](ollama.md) | Local LLM inference (NVIDIA RTX 2000 Ada) | 11434 |
| [ollama-queue-proxy.md](ollama-queue-proxy.md) | Queuing, auth, and routing layer | 11435 |
| [open-webui.md](open-webui.md) | Multi-model chat UI | 8080 |
| [searxng.md](searxng.md) | Private meta-search engine | 8888 |
| [searxng-mcp.md](searxng-mcp.md) | Web search + fetch cascade MCP | 8492 |
| [firecrawl.md](firecrawl.md) | JS-rendered web extraction | 3002 |
| [crawl4ai.md](crawl4ai.md) | Structured web crawling | 11235 |
| [reranker.md](reranker.md) | ML result reranking | 8484 |
| [hister.md](hister.md) | Browser history semantic search | 3006 |
| [kiwix.md](kiwix.md) | Offline Wikipedia / Stack Overflow / Arch Wiki | 8888 |

## How Agents Use These

Agents don't call Ollama or SearXNG directly. They use MCP servers:

- **searxng-mcp** — web search → fetch → rerank cascade (all agents)
- **ollama-queue-proxy** — serialized embedding/inference requests from memsearch and qmd
