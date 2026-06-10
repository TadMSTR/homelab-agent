# MCP Servers

The homelab-agent platform uses [scoped-mcp](../docs/components/scoped-mcp.md) to give each agent a controlled MCP tool surface. This is different from the direct Claude Desktop stdio-transport pattern documented in the previous version of this repo.

## Architecture

Each agent connects to a single scoped-mcp proxy. The proxy reads the agent's manifest and routes tool calls to the real MCP backend services — the agent never holds credentials or connects to backends directly.

```
Agent → scoped-mcp proxy → MCP backend services
              ↑
         manifest defines:
         - which tools are allowed
         - rate limits
         - HITL gates
         - argument filters
```

See [`docs/components/scoped-mcp.md`](../docs/components/scoped-mcp.md) for the full architecture and deployment guide.

## MCP Servers in This Platform

| Server | Doc | Port / Transport | Purpose |
|--------|-----|-----------------|---------|
| system-ops | [doc](../docs/components/system-ops.md) | :8282 HTTP | Shell, files, processes |
| qmd | [doc](../docs/components/owners-manual.md) | :8181 HTTP | Semantic + keyword search |
| memsearch-mcp | [doc](../docs/components/memsearch-mcp.md) | :8493 HTTP | Hybrid memory search |
| memory-metadata-mcp | [doc](../docs/components/memory-services.md) | :8490 HTTP | Memory note metadata queries |
| memory-search-mcp | [doc](../docs/components/memory-services.md) | :8491 HTTP | Full-text memory search |
| patchmon-mcp | [doc](../docs/components/patchmon-mcp.md) | subprocess | Apt patch tracking |
| dockhand-mcp | [doc](../docs/components/dockhand-mcp.md) | subprocess | Docker stack management |
| signoz-mcp | [doc](../docs/components/signoz-mcp.md) | :8492 HTTP | APM traces and logs |
| githost-mcp | [doc](../docs/components/githost-mcp.md) | subprocess | Git + Gitea/GitHub ops |
| searxng-mcp | [doc](../docs/components/searxng-mcp.md) | subprocess | Web search |
| langfuse-mcp | [doc](../docs/components/langfuse-mcp.md) | subprocess | LLM trace queries |
| loki-mcp | [doc](../docs/components/loki-mcp.md) | subprocess | Loki log queries |
| grafana-mcp | [doc](../docs/components/grafana-mcp.md) | :8014 SSE | Grafana dashboard queries |
| pm2-mcp | [doc](../docs/components/pm2-mcp.md) | :8486 HTTP | PM2 process management |
| task-queue-mcp | [doc](../docs/components/task-queue-mcp.md) | :8485 HTTP | Inter-agent task queue |
| agent-bus | [doc](../docs/components/agent-bus.md) | subprocess | Event logging + NATS |
| matrix-mcp | [doc](../docs/components/matrix-mcp.md) | :8487 HTTP | Matrix messaging |
| plane-mcp | [doc](../docs/components/plane-mcp.md) | :8495 HTTP | Issue tracking |
| graphiti | [doc](../docs/components/graphiti.md) | :8000 HTTP | Knowledge graph |
| nats-mcp | [doc](../docs/components/nats-mcp.md) | subprocess | NATS event queries |
| code-server-mcp | [doc](../docs/components/code-server-mcp.md) | :8498 HTTP | VS Code server integration |

## Manifests

Sanitized example manifests showing per-agent tool allowlists, HITL gates, and filters are in [`manifests/`](../manifests/).

## Previous Version

The previous version of this file (claudebox-era, Claude Desktop + stdio) is archived at tag `archive/claudebox-v1`.
