# MCP Servers

The homelab-agent platform uses [scoped-mcp](../docs/components/agent/scoped-mcp.md) to give each agent a controlled MCP tool surface. This is different from the direct Claude Desktop stdio-transport pattern documented in the previous version of this repo.

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

See [`docs/components/agent/scoped-mcp.md`](../docs/components/agent/scoped-mcp.md) for the full architecture and deployment guide.

## MCP Servers in This Platform

| Server | Doc | Port / Transport | Purpose |
|--------|-----|-----------------|---------|
| system-ops | [doc](../docs/components/mcp-servers/system-ops.md) | :8282 HTTP | Shell, files, processes |
| qmd | [doc](../docs/components/cicd/owners-manual.md) | :8181 HTTP | Semantic + keyword search |
| memsearch-mcp | [doc](../docs/components/memory/memsearch-mcp.md) | :8493 HTTP | Hybrid memory search |
| memory-metadata-mcp | [doc](../docs/components/memory/memory-services.md) | :8490 HTTP | Memory note metadata queries |
| memory-fulltext-mcp | [doc](../docs/components/memory/memory-services.md) | :8491 HTTP | Full-text memory search (renamed from `memory-search-mcp` 2026-07-23) |
| patchmon-mcp | [doc](../docs/components/mcp-servers/patchmon-mcp.md) | subprocess | Apt patch tracking |
| dockhand-mcp | [doc](../docs/components/mcp-servers/dockhand-mcp.md) | subprocess | Docker stack management |
| signoz-mcp | [doc](../docs/components/observability/signoz-mcp.md) | :8492 HTTP | APM traces and logs (v0.3.0) |
| githost-mcp | [doc](../docs/components/mcp-servers/githost-mcp.md) | subprocess | Git + GitHub/Gitea/GitLab ops (v0.5.0, 45 tools, HITL merge gate on GitHub/GitLab merge tools) |
| searxng-mcp | [doc](../docs/components/ai-search/searxng-mcp.md) | :8504 HTTP | Web search |
| langfuse-mcp | [doc](../docs/components/observability/langfuse-mcp.md) | subprocess | LLM trace queries |
| loki-mcp | [doc](../docs/components/observability/loki-mcp.md) | subprocess | Loki log queries |
| grafana-mcp | [doc](../docs/components/observability/grafana-mcp.md) | :8014 SSE | Grafana dashboard queries |
| pm2-mcp | [doc](../docs/components/mcp-servers/pm2-mcp.md) | :8486 HTTP | PM2 process management |
| task-queue-mcp | [doc](../docs/components/agent/task-queue-mcp.md) | :8485 HTTP | Inter-agent task queue |
| agent-bus | [doc](../docs/components/agent/agent-bus.md) | subprocess | Event logging + NATS |
| matrix-mcp | [doc](../docs/components/agent/matrix-mcp.md) | :8487 HTTP | Matrix messaging |
| plane-mcp | [doc](../docs/components/mcp-servers/plane-mcp.md) | :8495 HTTP | Issue tracking |
| graphiti | [doc](../docs/components/memory/graphiti.md) | :8000 HTTP | Knowledge graph |
| nats-mcp | [doc](../docs/components/agent/nats-mcp.md) | subprocess | NATS event queries |
| code-server-mcp | [doc](../docs/components/mcp-servers/code-server-mcp.md) | :8498 HTTP | VS Code server integration |
| backrest-mcp | [doc](../docs/components/mcp-servers/backrest-mcp.md) | :8626 HTTP | Backup plan status, snapshots, restore |

## Manifests

Sanitized example manifests showing per-agent tool allowlists, HITL gates, and filters are in [`manifests/`](../manifests/).

## Previous Version

The previous version of this file (claudebox-era, Claude Desktop + stdio) is archived at tag `archive/claudebox-v1`.
