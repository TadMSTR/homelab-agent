# homelab-agent

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-enabled-blueviolet)](https://claude.ai/code)

![Helm Platform](docs/assets/banner.png)

I rebuilt my AI homelab platform on more capable hardware and documented everything from scratch. Five purpose-built agents share a memory system, run unattended builds, and stay reachable from any Matrix client or browser. This repo is that documentation — every Docker service, every PM2 process, every design decision that got it here.

The platform is called **Helm**. The host is **forge** — a [Minisforum MS-A2](https://www.minisforum.com/product/ms-a2/) running Debian 13, 55+ containers, and a multi-agent Claude Code engine.

> Previously documented a claudebox-era build. That build is archived at tag `archive/claudebox-v1` and branch `archive/claudebox`.

## Architecture

Three layers, each independently useful.

```
┌────────────────────────────────────────────────────────────────┐
│  Layer 3: Multi-Agent Claude Code Engine                       │
│  5 resident agents · scoped-mcp · Matrix dispatch             │
│  agent-bus · memory pipeline · knowledge graph                 │
├────────────────────────────────────────────────────────────────┤
│  Layer 2: Docker Service Stack (60+ containers, 22 stacks)     │
│  SWAG/Authentik · Ollama (NVIDIA GPU) · Langfuse · SigNoz      │
│  Synapse · SearXNG · Milvus · Graphiti · Temporal · NATS       │
├────────────────────────────────────────────────────────────────┤
│  Layer 1: Host                                                 │
│  Minisforum MS-A2 · AMD Ryzen 9 9955HX (16c/32t) · 96 GB      │
│  NVIDIA RTX 2000 Ada · 5.4 TB NVMe · Debian 13 trixie         │
└────────────────────────────────────────────────────────────────┘
```

### Layer 1 — Host

| | |
|-|-|
| **Machine** | Minisforum MS-A2 |
| **CPU** | AMD Ryzen 9 9955HX — 16 cores / 32 threads, up to 5.0 GHz |
| **RAM** | 96 GB DDR5 |
| **Storage** | 1.8 TB NVMe (Crucial P310) + 3.6 TB NVMe (Crucial P3 Plus) |
| **GPU** | NVIDIA RTX 2000 Ada — Ollama inference, GPU-accelerated embeddings |
| **iGPU** | AMD Radeon (Granite Ridge) — Grafana image rendering |
| **OS** | Debian 13 trixie |

The two GPUs do separate jobs: the NVIDIA card handles LLM inference via Ollama; the AMD iGPU handles Grafana's image renderer for panel exports and screenshots. Neither workload competes with the other.

### Layer 2 — Docker Service Stack

60+ containers across 22 compose stacks. SWAG handles SSL termination and routing; Authentik provides SSO with domain-level forward auth and per-service OIDC.

**Foundation**

| Service | What It Does |
|---------|-------------|
| [SWAG](docs/components/swag.md) | Nginx reverse proxy, wildcard SSL via Let's Encrypt + Cloudflare DNS-01 |
| [Authentik](docs/components/authentik.md) | SSO — domain-level forward auth + per-service OIDC |
| [Vaultwarden](docs/components/vaultwarden.md) | Self-hosted Bitwarden-compatible password manager |
| [Vault](docs/components/vault.md) | HashiCorp Vault — secret management |
| [Dockhand](docs/components/dockhand.md) | Docker stack manager UI |

**Observability**

| Service | What It Does |
|---------|-------------|
| [Grafana](docs/components/grafana-alloy.md) + [InfluxDB 3](docs/components/influxdb.md) | Dashboards and time-series metrics |
| [Loki](docs/components/grafana-alloy.md) + [Alloy](docs/components/grafana-alloy.md) | Container log aggregation |
| [Prometheus](docs/components/telegraf.md) + [Telegraf](docs/components/telegraf.md) | Metrics scraping and system metrics collection |
| [SigNoz](docs/components/signoz.md) | APM and distributed tracing |
| [Langfuse](docs/components/langfuse.md) | LLM observability — token usage, cost, trace quality |

**AI & Search**

| Service | What It Does |
|---------|-------------|
| [Ollama](docs/components/ollama.md) | Local LLM inference on NVIDIA RTX 2000 Ada |
| [Open WebUI](docs/components/open-webui.md) | Multi-model chat UI fronting Ollama |
| [SearXNG](docs/components/searxng.md) | Private meta-search engine — agent web search backend |
| [Firecrawl](docs/components/firecrawl.md) | Web content extraction to LLM-ready markdown |
| [Crawl4AI](docs/components/crawl4ai.md) | Structured web crawling with schema extraction |
| [Reranker](docs/components/reranker.md) | ML reranking for search result quality |
| [Hister](docs/components/hister.md) | Browser-based semantic search over the agent knowledge corpus |

**Memory & Knowledge**

| Service | What It Does |
|---------|-------------|
| [Memory Stack](docs/components/memory-stack.md) — Milvus + OpenSearch | Vector search + full-text search backends for agent memory |
| [Graphiti + Neo4j](docs/components/graphiti.md) | Temporal knowledge graph — infrastructure topology and entity relationships |

**Agent Infrastructure**

| Service | What It Does |
|---------|-------------|
| [Synapse + Ketesa](docs/components/synapse.md) | Self-hosted Matrix homeserver — agent communications |
| [NATS](docs/components/nats.md) | Event bus — agent lifecycle events, JetStream persistence |
| [task-queue-mcp](docs/components/task-queue-mcp.md) | Containerized task queue with MCP tool surface |
| [CloudCLI](docs/components/cloudcli.md) | Browser-based Claude Code UI |

**CI/CD & Workflow**

| Service | What It Does |
|---------|-------------|
| [Woodpecker CI](docs/components/woodpecker.md) | Self-hosted CI — pipeline execution for Gitea repos |
| [Temporal](docs/components/temporal.md) | Durable workflow execution engine for agent build pipelines |

**Platform Maintenance**

| Service | What It Does |
|---------|-------------|
| [Patchmon](docs/components/patchmon.md) | Apt package tracking and patch management |
| [Renovate](docs/components/renovate.md) | Dependency update scanning (non-Docker) |

### Layer 3 — Multi-Agent Claude Code Engine

Five resident agents — `sysadmin`, `research`, `developer`, `writer`, `security` — run as scoped Claude Code projects. Each gets:

**Scoped tool surface** — [scoped-mcp](docs/components/scoped-mcp-forge.md) proxies only the tools the agent's manifest allows. Agents see tool results, never credential values. A credential rotation in one agent has zero effect on others.

**Matrix dispatch** — [matrix-dispatcher-forge](docs/components/matrix-dispatcher-forge.md) polls each agent's Matrix room for messages from the operator and routes them into the right agent's project directory. Send a message from any Matrix client; the agent picks it up and replies in-thread.

**Persistent memory** — a [three-tier memory system](docs/components/memory-architecture.md) (session → working → distilled) backed by Milvus vector search, OpenSearch full-text, a SQLite metadata index, and a Neo4j knowledge graph. Session notes written mid-build are searchable in the next session.

**Event ledger** — [agent-bus](docs/components/agent-bus.md) logs every cross-agent event (handoffs, task completions, audit requests) to a JSONL trail, federated to NATS JetStream.

**PM2-managed background services:**

| Process | What It Does |
|---------|-------------|
| `agent-bus` | Inter-agent event log → NATS federation + ntfy alerting |
| `memsearch-watch` | Periodic memory indexing (polls every 5 minutes) |
| `memsearch-mcp` | Hybrid vector+BM25+reranker memory search MCP |
| `memsearch-summarize` | Summarises raw session transcripts via Anthropic API |
| `qmd` | Semantic + keyword search MCP over 9 000+ docs |
| `memory-metadata-mcp` | Structured queries over memory note metadata |
| `memory-search-mcp` | Full-text memory search via OpenSearch |
| `signoz-mcp` | SigNoz APM query MCP — traces, logs, metrics |
| `temporal-build-worker` | Temporal worker — drives autonomous build pipelines |
| `matrix-mcp-forge` | Matrix messaging tool surface for forge agents |
| `matrix-dispatcher-forge` | Routes operator Matrix messages → agent project dirs |
| `matrix-admin-bot-forge` | Matrix account provisioning bot |
| `system-ops` | Homelab-ops MCP server — shell, files, processes |
| `cloudcli` | CloudCLI web UI on port 3001 |

## What's In This Repo

```
docs/components/   — Per-service operational reference (76 docs)
docs/phases/       — Build completion records (23 phases, what was built and when)
docs/operations/   — Operational runbooks
docs/diagrams/     — Architecture diagrams
CHANGELOG.md       — Build history summary
docker/            — Docker Compose stacks with .env.example templates
scripts/           — Maintenance and monitoring scripts
manifests/         — Sanitized agent manifest examples
claude-code/       — Claude Code project configs and CLAUDE.md examples
pm2/               — PM2 ecosystem config and process documentation
```

**Start with [`docs/phases/`](docs/phases/)** for the build history — each phase doc explains what was added, what changed, and what security findings were resolved.

**Use [`docs/components/`](docs/components/)** for operational details on any specific service — configuration, ports, dependencies, and integration points without reading the compose file.

## Prerequisites

To replicate this stack:

- A machine with 32 GB+ RAM (96 GB if running 5 agents concurrently with local LLMs)
- An NVIDIA GPU for local Ollama inference, or a remote Ollama API endpoint
- Debian/Ubuntu with Docker CE + Compose
- A domain name — SWAG uses DNS-01 validation via Cloudflare (no port forwarding required)
- Claude Pro or Max subscription + Anthropic API key (for the Claude Code agents)

The observability and service stacks run without the GPU. The agents run without local Ollama — they use the Anthropic API directly. Local inference matters for embedded model calls (embeddings, reranking, query expansion) and for cost when running many agent sessions concurrently.

## Related

- [Minisforum MS-A2](https://www.minisforum.com/product/ms-a2/) — the hardware forge runs on

## License

MIT
