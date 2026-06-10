# memsearch-mcp

FastMCP server wrapping the memsearch semantic memory search library. Exposes hybrid
vector+BM25+reranker search and index-refresh tools to forge agents over streamable-http MCP
transport.

- **PM2 process:** `memsearch-mcp`
- **Endpoint:** `http://127.0.0.1:8493/mcp`
- **Transport:** streamable-http
- **Interpreter:** `/opt/venvs/memsearch/bin/python3`
- **Repo:** `~/repos/personal/memsearch-mcp/`

## What It Does

Agents call `search_memory` with a natural-language query and get ranked results from all
indexed memory: session notes (per-project `.memsearch/memory/` dirs), working-tier notes
(`~/.claude/memory/`), and docs. Each result includes the path, a text snippet, the nearest
heading, a relevance score, and a tier label so the agent knows where the information lives.

`index_memory` lets agents trigger a re-index after writing new memory files — useful when
an agent wants to search notes it just wrote in the same session. It's path-whitelisted
(`~/.claude/memory/`, `~/.claude/projects/`, `/opt/agents/memory/`) and is denylisted for
security, research, and writer agents.

## Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `MEMSEARCH_MCP_PORT` | `8493` | Listen port |
| `LOG_LEVEL` | `INFO` | structlog log level |

Configuration for the underlying memsearch library (Milvus URI, embedding model, reranker) is
read from the memsearch config file. See [memsearch.md](memsearch.md) for details.

## Dependencies

| Service | Required | Purpose |
|---------|----------|---------|
| `milvus` (19530) | Yes | Vector store — search fails without it |
| `ollama-queue-proxy` (11435) | Yes | Embedding inference for `index_memory` |
| `memsearch-watch` (PM2) | Indirect | Keeps the index current; `search_memory` is stale if watch is down |

memsearch-mcp starts successfully even if its dependencies are down. Individual tool calls
will return `{"error": "..."}` rather than crashing.

## Operations

```bash
# Status
pm2 status memsearch-mcp

# Logs
tail -f ~/logs/memsearch-mcp.log

# Restart (e.g., after memsearch library update)
pm2 restart memsearch-mcp

# Health check
curl -s http://127.0.0.1:8493/mcp
```

## scoped-mcp Integration

All 5 forge agent manifests include memsearch-mcp:

| Agent | index_memory | search_memory |
|-------|-------------|---------------|
| research | denylisted | available |
| developer | available | available |
| writer | denylisted | available |
| security | denylisted | available |
| sysadmin | available | available |

Manifest snippet:

```yaml
- name: memsearch-mcp
  type: mcp_proxy
  url: "http://127.0.0.1:8493/mcp"
  tool_denylist:
    - "index_memory"   # present for research, writer, security
```

The `archival-search` skill (`~/.claude/skills/archival-search/SKILL.md`) uses memsearch-mcp
as its primary search backend, replacing the older `memory-search-mcp`.

## Related Docs

- [memsearch.md](memsearch.md) — memsearch library, polling watch daemon, reranker
- [memory-services.md](memory-services.md) — overview of all memory layer PM2 services
- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch storage backends
- [scoped-mcp-forge.md](scoped-mcp-forge.md) — manifest structure and agent tool surfaces
