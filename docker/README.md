# Docker Stacks

Docker Compose stacks for the homelab-agent platform running on forge. Each directory is a self-contained stack with a `docker-compose.yml` and a `.env.example` template.

## Layout

```
docker/
├── agent-platform/       # NATS, DragonflyDB (agent state), Ollama queue proxy
├── authentik/            # SSO — domain-level forward auth + OIDC
├── code-server/          # VS Code in browser
├── crawl4ai/             # Structured web crawling
├── crawler/              # Crawl4AI + Firecrawl composite stack
├── dockhand/             # Docker stack manager UI
├── firecrawl/            # Web content extraction to markdown
├── graphiti/             # Temporal knowledge graph (Neo4j + Graphiti MCP)
├── hister/               # Browser-based semantic search
├── langfuse/             # LLM observability
├── librechat/            # Multi-model chat UI
├── matrix/               # Matrix homeserver (Synapse + Ketesa)
├── memory-stack/         # Milvus + OpenSearch — vector and full-text search
├── nvidia-exporter/      # NVIDIA GPU metrics exporter for Prometheus
├── observability/        # Grafana + Loki + Alloy + InfluxDB + Prometheus + Telegraf
├── ollama/               # Local LLM inference
├── open-webui/           # Multi-model chat UI fronting Ollama
├── patchmon/             # Apt package tracking and patch management
├── plane/                # Project management
├── renovate/             # Dependency update scanning
├── reranker/             # ML reranking service
├── searxng/              # Private meta-search engine
├── signoz/               # APM and distributed tracing
├── swag/                 # Nginx reverse proxy, wildcard SSL
├── task-queue-mcp/       # Agent task queue with MCP tool surface
├── temporal/             # Durable workflow engine
├── vault/                # HashiCorp Vault — secret management
├── vaultwarden/          # Self-hosted Bitwarden-compatible password manager
└── woodpecker/           # Self-hosted CI/CD
```

## Dependency Order

Deploy in this order to satisfy network and service dependencies:

1. **swag** — creates `forge-net` network, SSL termination
2. **authentik** — SSO must be available before services that use forward auth
3. **vault** — secret backend; agents and services pull credentials from here
4. **observability** — creates `grafana-datasources` network used by other stacks
5. **matrix** — homeserver; agent communication depends on it
6. **agent-platform** — NATS, DragonflyDB, Ollama queue proxy
7. **ollama** — local LLM inference; needed by memsearch and embedding services
8. **memory-stack** — Milvus + OpenSearch; memsearch depends on Milvus
9. **graphiti** — knowledge graph; depends on Neo4j (included in compose)
10. **task-queue-mcp** — inter-agent task routing
11. All remaining stacks — can be deployed in any order after the above

## Usage

```bash
# Deploy a stack
cd docker/<stack>
cp .env.example .env
# Edit .env with your values
docker compose up -d

# Verify
docker compose ps
docker compose logs --tail=50
```

## Networking

All stacks attach to `forge-net` (external network created by the swag stack). Observability stacks additionally attach to `grafana-datasources`.

```bash
# Create networks (swag stack does this automatically, or manually):
docker network create forge-net
docker network create grafana-datasources
```

## Environment Files

Each stack with configurable secrets or settings ships with a `.env.example`. Copy to `.env` and fill in values before deploying.

Variable names with `${VAR}` in compose files reference the `.env` file. No default values for secrets are provided — all must be set explicitly.

## Sanitization

All compose files have had internal IPs replaced with placeholders:
- LAN host IPs → `<server-ip>`
- NAS/storage IPs → `<nas-ip>` and `<nas-subnet>`
- LAN subnet → `<lan-subnet>`
- Docker bridge gateway → `<docker-bridge-ip>`

Replace these placeholders with your actual values when deploying.
