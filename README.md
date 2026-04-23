<p align="center">
  <img src="docs/assets/banner.png" alt="homelab-agent banner" />
</p>

# homelab-agent

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-enabled-blueviolet)](https://claude.ai/code)

I run a multi-user AI platform out of a mini PC in my homelab. Claude has persistent context about my infrastructure, live tool access to my servers, purpose-built agents for specific tasks, and a web frontend accessible from any browser on the network. This repo documents the full build.

## What This Is

This is more than "I use AI to write scripts." It's a three-layer platform: a dedicated host running Claude Desktop with MCP server integrations for direct infrastructure access, a self-hosted Docker stack with LibreChat as the multi-user frontend and supporting AI services, and a multi-agent Claude Code engine with scoped memory, background jobs, and automated knowledge accumulation.

The LibreChat frontend is where the platform shows its depth. It's not just a chat UI — it hosts specialized agents, each configured with its own tools, context, and purpose. The first: a job search agent with multi-board scraping, resume scoring, and application tracking. More are being added. Any browser on the network can access the platform; anyone with an account can use the agents.

What makes it work over time is the memory system. Claude doesn't start from zero every session. It loads infrastructure context, recalls relevant decisions from past work, and accumulates knowledge automatically through nightly memory sync. Add the version-controlled infrastructure (everything the AI can touch is in git), and you have a system that can operate alongside you without being a liability.

Modular by design. Take the whole thing or just the parts that fit your setup. The system rewards customization — the more you shape it to how you actually work, the more useful it gets.

## How This Started

I watched a TechnoTim video on TrueNAS and Docker, needed a backup script, and used Claude to write it. The script worked, but Claude kept asking me the same questions about my setup every session. So I started writing down my infrastructure in markdown files and feeding them as context. That context system grew into a structured repository — profiles, preferences, infrastructure docs, project instructions — which I started calling the "prime directive."

Once Claude had persistent context about my environment, the interactions changed. Instead of explaining my setup every time, I could say "check if the Plex container is healthy on unraid" and it already knew unraid's IP, what monitoring tools were available, and how my Docker stacks were organized. That was the inflection point.

I built a dedicated mini PC (claudebox) to run Claude Desktop full-time with MCP tool integrations — direct access to Netdata, Grafana, GitHub, the filesystem, and a browser. Then I layered on a self-hosted service stack: reverse proxy with SSO, a multi-provider chat UI with purpose-built agents, semantic search over all my docs and repos, and a Claude Code web interface. On top of that, a multi-agent Claude Code engine with scoped memory, background jobs, and automated knowledge sync.

It grew organically from "AI writes me a script" to "AI operates alongside me as infrastructure."

## Recent Updates

See [CHANGELOG.md](CHANGELOG.md) for the full build history.

- **2026-04-22** — ollama-queue-proxy v0.2.0 deployed on claudebox: graphiti, jobsearch-mcp, searxng-mcp, and memsearch-watch all routing through the proxy; Valkey embedding cache active; model-aware routing to forge GPU; injection port for memsearch-watch (no Bearer support upstream). See [ollama-queue-proxy](docs/components/ollama-queue-proxy.md).
- **2026-04-21** — New public showcase repo: [ollama-queue-proxy](https://github.com/TadMSTR/ollama-queue-proxy) — smart pool manager for Ollama with three-tier priority queuing (high/normal/low), per-client API key auth with priority ceilings and concurrency caps, model-aware weighted routing, Valkey embedding cache, client injection ports, and keep_alive injection. Auth-first design: keys are scoped, management endpoints are gated separately, webhook SSRF covers IP literals and hostnames.
- **2026-04-12** — Autonomous build pipeline wired end-to-end: trigger-proxy (n8n→RemoteTrigger HTTP proxy with OAuth auto-refresh), task-dispatcher approval webhook + dead-letter queue, 8 agent manifests with RemoteTrigger IDs. Security hardening: X-Trigger-Secret timing-safe auth on trigger-proxy, 0600 file permissions for credentials and task queue YAMLs, 65536-byte body size limit. Docker Compose templates added for all 11 remaining active stacks (grafana, graphiti, milvus, n8n, nats, plane, temporal, crawl4ai, searxng-mcp-cache, task-queue-mcp, blog-preview) — stacks table doubles from 10→20.
- **2026-04-08** — jobsearch-mcp v2: Ollama bge-m3 embeddings replace Voyage AI, Valkey enrichment cache, three-tier JD pipeline (Firecrawl→Crawl4AI→rawFetch), five new resume profile tools (`build_profile`/`save_profile`/`tailor_resume`/get/delete), ATS scoring, job-watcher email alerts, USAJobs as default source. Stack 3→5 containers. Also: pm2-mcp (structured PM2 CLI access for agents), ntfy-mcp (native push notification tool), searxng-mcp v3.1.0 (recency weighting).

## Architecture

The system has three layers. Each is independently useful — you don't need all three.

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Multi-Agent Claude Code Engine                │
│  CLAUDE.md hierarchy · scoped memory · memsearch        │
│  knowledge graph · agent-bus · Temporal · mem pipeline  │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Self-Hosted Service Stack (Docker)            │
│  SWAG/Authelia · LibreChat · purpose-built agents       │
│  qmd · CloudCLI · SearXNG · Grafana · NATS · Temporal   │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Host & Core Tooling                           │
│  Debian mini PC · Claude Desktop · MCP servers          │
│  Guacamole remote access                                │
└─────────────────────────────────────────────────────────┘
```

### Layer 1 — Host & Core Tooling

The foundation is a dedicated machine running Claude Desktop with MCP (Model Context Protocol) server integrations. MCP gives Claude direct, structured access to your infrastructure tools — not copy-pasting outputs into a chat window, but live tool calls.

**Hardware:** GMKTec K11 mini PC — AMD Ryzen 9 8945HS, 32GB RAM, 2TB NVMe. Plenty for local embeddings and multiple Docker containers. Any modern mini PC or repurposed desktop works.

**OS:** Debian 13 (trixie). Nothing special about the choice — stable, familiar, good Docker support.

**Claude Desktop** runs as the primary AI interface, with MCP servers providing tool access:

| MCP Server | What It Does | Built by |
|------------|-------------|----------|
| Backrest | Trigger backup plans, fetch operation history for restic-based backups | me |
| basic-memory | Persistent knowledge base as Obsidian-compatible markdown files | community |
| Bluesky | Social media management via AT Protocol | me (fork) |
| Desktop Commander | Filesystem operations, terminal commands, process management (Claude Desktop) | Anthropic |
| GitHub | Repo management, issues, PRs, code search across multiple accounts | Anthropic |
| Grafana | Dashboard management, alert rules, Loki log queries, InfluxDB metrics | Grafana |
| homelab-ops | Shell, file, and process operations over HTTP (Claude Code + LibreChat) | me |
| pm2-mcp | PM2 process manager — list services, tail logs, restart/stop/start via structured `pm2 jlist` output (Claude Code) | me |
| InfluxDB | Time-series queries and writes for Telegraf-shipped metrics | community |
| jobsearch-mcp | Multi-board job search, resume scoring, application tracking (LibreChat) | me |
| memsearch | Memory recall from past Claude Code sessions (plugin, not MCP) | community |
| Netdata | Real-time metrics from any monitored host (CPU, RAM, disk, containers, alerts) | Netdata |
| Playwright | Browser automation — navigate, click, fill forms, take screenshots | Anthropic |
| qmd | Semantic search over repos, docs, and agent memory — stdio and HTTP modes | community |
| searxng-mcp | Private web search via SearXNG with ML reranking, Valkey result caching, domain filtering/boosting, Ollama query expansion, and LLM summarization | me |
| TrueNAS | Datasets, pools, snapshots, users, SMB/NFS/iSCSI via REST API | community |
| Unraid | Array status, disk health, Docker containers, shares via GraphQL API | me |

For config patterns, standalone value ratings, and a prioritized adoption path, see [`mcp-servers/README.md`](mcp-servers/README.md).

**Guacamole** provides browser-based remote desktop access to the machine. Useful when you're away from the desk but need to interact with Claude Desktop's GUI.

**Standalone value:** Even without Layers 2 and 3, a dedicated machine running Claude Desktop with MCP servers is a significant upgrade over using Claude in a browser tab. The MCP integrations alone — being able to say "check disk health on unraid" or "query Grafana for the last hour of CPU on atlas" — change how you interact with your infrastructure.

### Layer 2 — Self-Hosted Service Stack

Docker containers on the same host, fronted by a reverse proxy with SSO. These provide web-accessible AI tools for the whole household or team, not just whoever is sitting at the Claude Desktop session.

| Service | What It Does | Why It's Here |
|---------|-------------|---------------|
| **LibreChat** | Multi-provider chat UI (Anthropic, OpenAI, Ollama, etc.) | The multi-user AI platform. Hosts specialized agents with their own tools and context. Built-in memory, RAG, MCP integration, and web search pipeline. See [Purpose-Built Agents](#purpose-built-agents) below. |
| **SearXNG** | Private meta-search | Self-hosted search backend. Aggregates results from multiple engines with no API keys or per-query costs. Powers LibreChat's web search pipeline. |
| **SWAG** | Nginx reverse proxy with Let's Encrypt wildcard SSL | Single entry point for all `*.yourdomain` services. DNS validation via Cloudflare — internal-only domain, no ports exposed to the internet. |
| **Authelia** | SSO authentication gateway | One login for all services. SWAG has first-class Authelia support — two lines uncommented per proxy conf. |
| **Grafana + InfluxDB + Loki** | Local agent observability stack | Dashboards for Claude Code session metrics, token usage, estimated costs, and LibreChat activity. Loki for self-healing system logs. Separate from atlas infrastructure monitoring — see [grafana-claudebox](docs/components/grafana-claudebox.md) and [grafana-observability](docs/components/grafana-observability.md). |
| **Dockhand** | Docker stack manager UI | Visual management of Docker Compose stacks. |
| **CloudCLI** | Claude Code browser UI _(PM2 host service, not Docker)_ | Browser-based Claude Code interface with file explorer, multi-session tabs, and push notifications. Runs as a PM2-managed Node.js process on the host, proxied through SWAG. Primary day-to-day interface for infrastructure work. |
| **Open Notebook** | AI research/notebook tool | Document analysis and research with SurrealDB backend. |
| **NATS + JetStream** | Agent event bus | NATS 2.10 with JetStream persistence. Task lifecycle events flow here from the dispatcher; inter-agent events (handoffs, audit requests, task failures) federate here from agent-bus. Three streams: TASKS (30d), AGENT_EVENTS (7d), AGENT_BUS (30d, 2-min dedup). Additive to the file queue — source of truth stays in the filesystem. Monitoring dashboard proxied via SWAG. See [nats-jetstream](docs/components/nats-jetstream.md). |
| **Graphiti + Neo4j** | Temporal knowledge graph | Neo4j 5.26.0 graph database with Graphiti MCP for entity extraction and relationship mapping. Captures infrastructure topology — services, hosts, networks, agents — with temporal validity. Fed by memory-flush (real-time) and memory-sync (nightly). See [graphiti](docs/components/graphiti.md). |
| **Temporal** | Durable workflow engine | Five-container stack (server, UI, PostgreSQL, two init containers for schema migration). Provides fault-tolerant multi-phase workflow execution — if a phase fails or the system restarts mid-build, it resumes from the last checkpoint rather than starting over. See [temporal](docs/components/temporal.md). |
| **n8n** | Workflow automation | n8n with Postgres backend. Handles webhook-triggered workflows and event routing between the AI platform and external systems. Task queue and agent manifests mounted read-only for agent-triggered workflows. See [n8n](docs/components/n8n.md). |
| **Helm Dashboard** | CloudCLI monitoring plugin | Browser tab for observing unattended agent builds — agent sessions, memory state, handoff queue, knowledge graph, PM2/Docker infrastructure, Plane work items, and WebSocket live updates. Pairs with auto mode configuration for walk-away workflows. See [helm-dashboard](docs/components/helm-dashboard.md) and [auto-mode](docs/components/auto-mode.md). |
| **qmd** | Semantic search MCP server | Hybrid search (BM25 + vector + LLM reranking) over all repos, docs, and agent memory. Local embeddings via GGUF models, GPU-accelerated on AMD iGPU via Vulkan. |
| **Hister** | Browser-based memory search | Self-hosted semantic + keyword search over the Claude memory corpus (~500 files: agent memory, prime-directive, build plans, platform docs). Independent of live Claude sessions — search past decisions from any browser. Semantic search via `nomic-embed-text` on the forge GPU; Bleve full-text keyword index; SearXNG fallback on zero results. Web UI behind Authelia SSO; MCP endpoint at `/mcp` for programmatic access. See [hister](docs/components/hister.md). |
| **ollama-queue-proxy** | Ollama pool manager | Smart pool manager for the Ollama fleet — per-client API key auth with priority ceilings and concurrency caps, three-tier priority queue (high/normal/low), model-aware routing to whichever host has the model already loaded, Valkey embedding cache for repeated RAG requests (skips queue and upstream on hit), injection ports for clients without Bearer support, and keep_alive injection to prevent cold-load latency. All active Ollama consumers (graphiti, jobsearch-mcp, searxng-mcp, memsearch-watch) route through it. See [ollama-queue-proxy](docs/components/ollama-queue-proxy.md). |

All containers share a single Docker network. SWAG handles SSL termination and routes `chat.yourdomain`, `auth.yourdomain`, `cloudcli.yourdomain`, etc. to the appropriate container.

**Standalone value:** The SWAG + Authelia + LibreChat stack is useful even without Claude Desktop or the agent engine. LibreChat gives you a self-hosted ChatGPT-like interface that works with multiple AI providers, and Authelia keeps it locked down.

### Layer 3 — Multi-Agent Claude Code Engine

This is where it gets opinionated. Claude Code (the CLI tool) supports project-scoped context via `CLAUDE.md` files and experimental agent teams. Combined with semantic memory search and PM2-managed background jobs, this creates a persistent, multi-agent system that accumulates knowledge over time.

**CLAUDE.md Hierarchy:**

```
~/.claude/CLAUDE.md                          ← Root context (loaded every session)
~/.claude/projects/homelab-ops/CLAUDE.md     ← Infrastructure management agent
~/.claude/projects/dev/CLAUDE.md             ← Code development agent
~/.claude/projects/research/CLAUDE.md        ← Technical research agent
~/.claude/projects/memory-sync/CLAUDE.md     ← Automated knowledge distillation
```

The root CLAUDE.md contains infrastructure topology, key paths, and global rules. Each project CLAUDE.md adds domain-specific context, available tools, and conventions. When you start a Claude Code session in a project directory, it loads the root + project context automatically.

**Scoped Memory:**

```
~/.claude/memory/
├── shared/              ← Cross-agent knowledge (infrastructure decisions, system context)
└── agents/
    ├── homelab-ops/     ← Infra-specific learnings
    ├── dev/             ← Development notes
    └── research/        ← Research findings
```

Agents read from shared + their own directory, write to their own directory. Cross-agent knowledge goes to shared. This prevents context bleed — the dev agent doesn't need to know about last week's disk replacement on unraid.

**memsearch** provides semantic search over the memory directories using local sentence-transformer embeddings and a vector database. The Claude Code plugin auto-injects relevant memories at session start and on each prompt. No API keys, no cloud services — runs entirely on the local CPU. **memsearch-watch** (PM2, always-on) keeps the index current by re-indexing all memory directories within 5 seconds of any write — so context captured mid-session is immediately searchable without waiting for a nightly batch. The **archival-search** skill provides a unified query across all three memory tiers (session, working, distilled) in a single pass, with results labeled by source tier. See [`docs/components/memsearch.md`](docs/components/memsearch.md) for configuration details.

**Graphiti knowledge graph** adds structured relationship queries on top of the flat-file memory system. A Neo4j-backed temporal graph captures infrastructure topology — which services run on which hosts, what depends on what, how the architecture evolved. Fed automatically by real-time memory-flush and nightly memory-sync batch ingestion. Agents query it with `search_memory_facts` and `search_nodes` when they need relational answers rather than text search. See [`docs/components/graphiti.md`](docs/components/graphiti.md).

**agent-bus** is the inter-agent event ledger — a FastMCP server that logs all cross-agent events (handoffs, audit requests, task completions, failures) to a JSONL audit trail and federates them to NATS JetStream. Every coordination action between agents leaves a durable, queryable record. This is what makes multi-agent workflows debuggable: when something goes wrong, the full event sequence is preserved. See [`docs/components/agent-bus.md`](docs/components/agent-bus.md).

**Temporal** provides durable workflow execution for long-running, multi-phase build processes. If a workflow is interrupted mid-phase (system restart, transient error), Temporal resumes from the last checkpoint rather than starting over. The Helm build automation runs through Temporal — each build phase is an activity with heartbeating and timeout guarantees. See [`docs/components/temporal.md`](docs/components/temporal.md).

**PM2 Background Agents:**

| Service | Schedule | What It Does |
|---------|----------|-------------|
| memsearch-watch | always-on | Re-indexes all memory directories within 5 seconds of any write — keeps semantic search current without waiting for the nightly batch |
| agent-bus | always-on | FastMCP server logging all cross-agent events (handoffs, audit requests, task failures) to a JSONL ledger, federated to NATS JetStream. The inter-agent audit trail. |
| task-dispatcher | Every 2 min | Routes submitted tasks between agents — auto-approves low-risk, gates medium/high via ntfy. Exponential backoff retry on routing failures. Publishes lifecycle events to NATS. |
| docker-stack-backup | 1:00 AM daily | Stops containers, rsyncs appdata to NFS, restarts |
| memory-promote-daily | 11:00 PM daily | Promotes session transcripts from the last 48h to working-tier notes using a smaller, faster model. Context from the day’s work is searchable the next morning. |
| memory-pipeline | 4:00 AM daily | Orchestrator: runs memsearch-compact → qmd-reindex in sequence after nightly promotions. Keeps the semantic search indexes fresh. |
| doc-sync-daily | 3:00 AM daily | Fetches official docs for all configured services, chunks them, and writes to the memsearch-indexed doc cache. Agents query cached docs instead of live URLs during task execution. |
| memory-sync-weekly | Mondays 7:00 AM | Promotes 14-day-old working notes to the distilled tier, expires 90-day notes, runs graph entity dedup. The expensive weekly pass using a more capable model. |
| resource-monitor | Every 6 hours | Checks RAM, disk, Docker health, PM2 status, NFS mounts; alerts via ntfy |
| dep-update-check | Wednesdays noon | Checks for updates to pinned dependencies (qmd, memsearch, Authelia, Claude Code) |
| doc-health-daily | 10:00 PM daily | Targeted doc scan on files touched that day — drift, index entries, sanitization. Zero-cost if nothing was edited. |
| doc-health | Sundays 11:00 PM | Full weekly doc audit — drift, coverage, staleness, sanitization, structural integrity |
| librarian-weekly | Mondays 6:00 AM | Diffs memory and semantic search against the prime-directive repo, commits missing or updated skill files, keeps the navigation index current |

See [`pm2/ecosystem.config.js.example`](pm2/ecosystem.config.js.example) for full configuration including an optional upstream issue watcher.

**Standalone value:** The CLAUDE.md hierarchy alone is worth adopting. Even without memsearch or the background agents, giving Claude Code structured context about your infrastructure dramatically improves the quality of its responses. Start with a root CLAUDE.md and one project, expand from there.

## Purpose-Built Agents

LibreChat isn't just a chat interface — it's the platform that hosts specialized agents, each configured with their own MCP servers, system prompt, and domain context. The difference from a generic AI chat: these agents know their job, have the right tools wired up, and keep state across sessions.

**Job Search Agent** — the first purpose-built agent in the stack. Backed by its own FastMCP server with tools for multi-board job scraping, resume scoring against job descriptions, and application tracking in Postgres. A user can ask "find senior DevOps roles remote in the US, score them against my resume, and add the top five to the tracker" and get back structured results — not a list of links.

The agent/platform model means adding a new agent is a matter of writing a FastMCP server and configuring it in LibreChat. The infrastructure (reverse proxy, SSO, memory, search) is already there. More agents are being added as new use cases emerge.

See [`docs/components/jobsearch-mcp.md`](docs/components/jobsearch-mcp.md) for the job search agent's architecture and the pattern for building additional agents.

The job search agent is what my situation needed. Someone else might build a home energy monitoring agent, a media request agent, something for tracking a health condition, or an agent scoped entirely to their homelab infrastructure. The platform doesn't prescribe what agents you build — it provides the infrastructure (auth, reverse proxy, memory, search) and gets out of the way. The useful thing isn't the job search agent specifically; it's that the slot exists and you can fill it with whatever fits your life.

## The Memory / Context System

This is the connective tissue that makes the whole thing more than the sum of its parts. Most people's experience with AI assistants is stateless — every conversation starts from zero. This system has five layers of persistent context:

1. **Prime directive repo** — Stable configuration: infrastructure docs, project instructions, profile/preferences, deployment scripts. Loaded at session start via CLAUDE.md references and qmd search. This is the source of truth.

2. **Core context** — An always-visible 40-line context block injected at every session start. Contains the user profile, active projects, key constraints, and recent decisions. Sits above the context window's compression threshold so critical facts never scroll out mid-session.

3. **Per-agent scoped memory** — Session summaries and learnings written by agents during their work. Organized by agent (shared/, homelab-ops/, dev/, research/) to prevent context bleed. Indexed by memsearch for automatic recall in future sessions. **memsearch-watch** keeps the index current in real time (5-second debounce) so notes written mid-session are searchable in the same session. A three-tier pipeline (session → working → distilled) ensures raw notes are reviewed, curated, and promoted to permanent storage.

4. **Knowledge graph** — A Neo4j-backed temporal knowledge graph (via [Graphiti](docs/components/graphiti.md)) that captures relationships between infrastructure entities — services, hosts, networks, agents, configurations. File-based memory handles narrative knowledge well; the graph handles "what connects to what" queries. Fed automatically by memory-flush (real-time) and memory-sync (nightly batch).

5. **Documentation cache** — A local library of official service documentation (42 services: Grafana, Loki, SWAG, Authentik, Compose, and more), fetched nightly, chunked by heading, and indexed in memsearch alongside session memory. Agents query cached docs during task execution instead of fetching live URLs — no network dependency, no stale training data. Managed by `doc-sync-daily` (PM2, 3 AM). See [`docs/components/doc-sync.md`](docs/components/doc-sync.md).

6. **Automated memory pipeline** — Three scheduled jobs handle different parts of the promotion cycle. **memory-promote-daily** (11 PM) promotes same-day session transcripts to working-tier notes using a faster model — context from the day's work is searchable the next morning. **memory-pipeline** (4 AM) runs memsearch compaction and qmd reindex after promotions settle. **memory-sync-weekly** (Mondays 7 AM) promotes 14-day-old working notes to the distilled tier, expires 90-day notes, and runs graph entity dedup. Knowledge accumulates and connects without manual curation. See [`docs/components/memory-pipeline.md`](docs/components/memory-pipeline.md).

The result: when I start a session on Monday, the agent already knows about the Docker stack change I made on Friday, the monitoring alert from Saturday, and the research I did on Sunday. It knows because the memory sync agent captured those events, the semantic search surfaced them as relevant context, and the knowledge graph connected them to the services they affected.

## What Makes This Different

Most AI homelab setups are "I use ChatGPT to write scripts." This is a persistent, context-aware system where the AI knows the infrastructure, remembers decisions, and improves over time.

**Persistent context, not copy-paste.** The AI doesn't need you to explain your setup every session. It loads infrastructure docs, reads recent memory, and picks up where you left off.

**Multi-user platform with purpose-built agents.** LibreChat gives the whole household or team access to specialized AI agents — not just one person's Claude Desktop session. Each agent is purpose-built: specific tools, specific context, specific job.

**Multi-agent with scoped memory.** Different Claude Code agents handle different domains without context bleed. The homelab-ops agent knows about Docker and monitoring. The dev agent knows about git workflows and code standards. They share infrastructure knowledge but keep domain-specific learnings separate.

**Automated knowledge accumulation.** The memory sync agent means you don't have to manually maintain documentation. Durable decisions and learnings flow from work sessions into the persistent knowledge base automatically. A temporal knowledge graph captures the relationships between infrastructure entities, so agents can query topology and dependencies — not just search text.

**Tool access, not just chat.** Via MCP, the AI can directly query Netdata metrics, check Grafana dashboards, search GitHub repos, read and write files, and automate browser tasks. It's not just answering questions — it's operating.

**Version-controlled infrastructure.** When AI agents have filesystem access, they will edit your config files directly — compose files, `.env` files, proxy confs. This is powerful, but it means you need version control on everything the AI can touch. All Docker compose files in this setup live in a git repo. Every change is tracked, diffable, and reversible. This isn't optional — it's the safety net that makes AI-assisted infrastructure management viable.

**Model-agnostic in practice.** The core engine runs on Claude, but LibreChat supports any provider (OpenAI, Ollama, etc.). SearXNG provides self-hosted search without API keys. The architecture doesn't lock you into a single vendor.

**This isn't a one-click stack.** There are polished prepackaged AI homelab solutions. This is not one of them. Every component here was chosen because it fit a specific need, and those choices are visible throughout the docs. Your version will look different — because your infrastructure is different, your workflow is different, and your brain works differently.

That's the point. When you build your own version of this, the AI knows about *your* storage server, *your* monitoring setup, *your* backup schedule and why it runs when it does. You wrote that context down, and it accumulated over time. A prepackaged solution can't ship with that. You build it, and building it is what makes it work.

## Planned Additions

The platform model makes it straightforward to add new integrations as new use cases emerge. On the roadmap:

**Home Assistant** — pulling device state and automation context into Claude's awareness. The goal is agents that understand what's happening in the house, not just on the servers.

**MQTT** — event-driven triggers for agents. When something happens on the network or in the house, an agent can respond rather than waiting to be asked.


## Using This Repo

This repo has two audiences: humans and AI agents.

**For humans:** Start with this README to understand the architecture, then [`docs/getting-started.md`](docs/getting-started.md) for the setup path. The docs are designed so you can stop at any layer and still have a working system. Component docs in [`docs/components/`](docs/components/) go deep on individual services.

**For AI agents:** [`index.md`](index.md) is a machine-readable navigation index of the entire repo — every file, what it covers, and task-based routing so an agent can load only the context it needs. It's designed for Claude Code, but it works with any AI that can read files.

This last point is worth calling out directly. If you want to build your own version of this stack, you can hand your AI assistant this repo and let it help you work through it:

```
I want to build an AI-powered homelab setup similar to the one in this repo.
Please read index.md to understand the full structure, then help me plan
which components to adopt based on my current setup.

My setup: [describe your hardware, OS, existing services]
My goals: [what you want Claude to be able to do]
```

The index covers every component and links to the relevant docs. Your AI can use it to ask the right questions, identify dependencies, and walk you through setup in the right order.

## Prerequisites

To run the full stack, you need:

- A dedicated machine (mini PC, old desktop, VM — 16GB+ RAM recommended, 32GB if running local models via Ollama)
- Debian/Ubuntu (or any Linux with Docker support)
- Docker CE + Compose
- Node.js 20+ and npm (for qmd, MCP servers)
- Python 3.11+ (for memsearch)
- A [Claude Pro or Max subscription](https://claude.ai) (for Claude Desktop + Claude Code)
- An Anthropic API key (for LibreChat)
- A domain name (for SWAG SSL — can be internal-only with DNS validation via Cloudflare)
- Optional: NFS server for backups (TrueNAS, Unraid, or any NFS-capable host)

You don't need all of this to get value. See [`docs/getting-started.md`](docs/getting-started.md) for clear stopping points where each layer is independently useful.

## Repo Structure

```
homelab-agent/
├── README.md                        ← You are here
├── index.md                         ← Machine-readable nav index for AI agents
├── docs/
│   ├── architecture.md              ← Detailed system architecture and data flows
│   ├── getting-started.md           ← Setup guide with stopping points per layer
│   └── components/                  ← Per-component deep dives
│       ├── swag.md                  ← Reverse proxy, Cloudflare DNS, proxy conf pattern
│       ├── authelia.md              ← SSO config, file-based user backend, SWAG integration
│       ├── librechat.md             ← Setup, web search pipeline, reranker wrapper, gotchas
│       ├── crawl4ai.md              ← Crawl4AI second-tier fetch fallback for searxng-mcp
│       ├── searxng.md               ← SearXNG + Valkey, shared search backend
│       ├── dockhand.md              ← Docker socket access, multi-host stack visibility
│       ├── open-notebook.md         ← SurrealDB, dual-port proxy config
│       ├── cloudcli.md              ← Claude Code web UI — file explorer, git, shell, MCP management
│       ├── auto-mode.md             ← Walk-away Claude Code config — approval skip, session limits, cost guardrails
│       ├── helm-dashboard.md        ← CloudCLI monitoring plugin — agent sessions, handoff queue, live updates
│       ├── agent-panel.md           ← Homelab operations panel — PM2, Docker, diagnostics, files
│       ├── diag-check.md            ← Scheduled diagnostics via agent panel API, failure alerts
│       ├── grafana-claudebox.md     ← Local Grafana + InfluxDB for agent observability
│       ├── grafana-observability.md ← Loki, image renderer, Alloy dual-destination log shipping
│       ├── graphiti.md              ← Temporal knowledge graph — Neo4j, entity ontology, data flow
│       ├── nats-jetstream.md        ← Agent event bus — JetStream streams, task lifecycle events, federation
│       ├── temporal.md              ← Durable workflow engine — 5-container stack, fault-tolerant build phases
│       ├── helm-temporal-worker.md  ← Helm build worker — async activity completion, phase orchestration
│       ├── n8n.md                   ← Workflow automation — webhook triggers, agent manifest routing
│       ├── plane.md                 ← Project management integration — work items, cycles, agent dispatch
│       ├── qmd.md                   ← Semantic search, dual transport, GPU acceleration
│       ├── memsearch.md             ← Memory recall for Claude Code, plugin integration
│       ├── hister.md                ← Browser-based memory search — semantic + keyword, preview shim
│       ├── ollama-queue-proxy.md    ← Ollama smart pool manager — auth, queuing, routing, embedding cache
│       ├── memory-sync.md           ← Knowledge distillation pipeline, PM2 cron
│       ├── memory-pipeline.md       ← 3-job memory schedule — real-time indexing, distillation, graph sync
│       ├── doc-sync.md              ← Local docs cache — service reference docs fetched, chunked, memsearch-indexed
│       ├── helm-ops-mcp.md          ← SSH-based MCP for remote Helm host — same tools as homelab-ops, remote transport
│       ├── librarian-weekly.md      ← Monday cron: syncs prime-directive repo against memory and skill files
│       ├── repo-sync-nightly.md     ← 23:30 cron: auto-commits doc repos, alerts on code repos with pending changes
│       ├── agent-workspace-scan.md  ← Hourly workspace marker validation, drift heal, CIA event emission
│       ├── agent-workspace-check.md ← Pre-edit resolver skill — two-party permission enforcement
│       ├── scoped-mcp.md            ← Per-agent MCP tool proxy — manifest-driven scoping, credential isolation, audit log
│       ├── agent-orchestration.md   ← Multi-agent coordination — handoff protocol, session sequencing
│       ├── task-dispatcher.md       ← Agent task queue — NATS-backed dispatch, 3-phase pipeline
│       ├── agent-bus.md             ← Inter-agent event bus — FastMCP server, NATS federation, event types
│       ├── inter-agent-communication.md ← Communication patterns — handoff protocol, CIA events
│       ├── security-agent.md        ← Security audit agent — automated scanning, severity gates
│       ├── doc-health.md            ← Weekly doc audit — drift, coverage, staleness, sanitization
│       ├── ai-cost-tracking.md      ← Claude Code JSONL parser, cost metrics, Telegraf pipeline
│       ├── homelab-ops-mcp.md       ← FastMCP HTTP tool server — shell, files, processes
│       ├── pm2-mcp.md               ← PM2 process manager MCP — list, log, restart/stop/start services
│       ├── claudebox-deploy.md      ← Provisioning script — full machine rebuild from NFS backup
│       ├── multi-host.md            ← Multi-host architecture — claudebox and remote build target coordination
│       ├── config-version-control.md ← Git tracking for docker/ and appdata configs
│       ├── jobsearch-mcp.md         ← Job search agent — multi-board scraping, resume scoring, tracking
│       ├── backups.md               ← Backrest/restic, Claude backup, Docker appdata backup
│       └── searxng-mcp.md           ← searxng-mcp v3.0.0 — tools, Valkey caching, domain filtering, Ollama expand/summarize
├── claude-code/
│   ├── CLAUDE.md.example            ← Root CLAUDE.md template
│   └── projects/                    ← Per-agent CLAUDE.md examples
│       ├── homelab-ops.md           ← Infrastructure management agent
│       ├── dev.md                   ← Development agent
│       ├── research.md              ← Research agent
│       └── memory-sync.md           ← Memory distillation agent
├── docker/
│   ├── swag/docker-compose.yml      ← Reverse proxy + wildcard SSL
│   ├── authelia/docker-compose.yml  ← SSO authentication gateway
│   ├── librechat/
│   │   ├── docker-compose.yml       ← Multi-provider chat + MongoDB + Meilisearch
│   │   └── librechat.yaml.example   ← LibreChat config with web search and MCP
│   ├── firecrawl-simple/docker-compose.yml  ← Web scraper for LibreChat search pipeline
│   ├── reranker/
│   │   ├── docker-compose.yml       ← Jina-compatible reranker wrapper
│   │   ├── Dockerfile               ← FlashRank + FastAPI build
│   │   └── main.py                  ← Reranker API source (~115 lines)
│   ├── dockhand/docker-compose.yml  ← Docker stack manager UI
│   └── open-notebook/docker-compose.yml  ← AI notebook + SurrealDB
├── pm2/
│   └── ecosystem.config.js.example  ← PM2 service definitions
├── scripts/
│   ├── docker-stack-backup.sh       ← Container-safe appdata backup with notifications
│   ├── qmd-reindex.sh               ← Semantic search re-indexing
│   ├── memory-sync.sh               ← Automated knowledge distillation
│   ├── check-resources.sh           ← Health monitoring with ntfy alerts
│   └── check-dep-updates.sh         ← Dependency update checker
└── mcp-servers/
    └── README.md                    ← MCP servers in use, config patterns, adoption path
```

## Related Repos

Third-party tools this stack depends on or was influenced by:

| Repo | Description |
|------|-------------|
| [tobi/qmd](https://github.com/tobi/qmd) | Semantic search engine with MCP server mode — hybrid BM25 + vector + LLM reranking |
| [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) | CloudCLI — Claude Code browser UI with file explorer, multi-session tabs, and notifications |
| [danny-avila/LibreChat](https://github.com/danny-avila/LibreChat) | Multi-provider chat interface with agents, MCP, memory, and RAG |
| [zilliztech/memsearch](https://github.com/zilliztech/memsearch) | Semantic memory search for markdown knowledge bases — Claude Code plugin for session recall |
| [letta-ai/letta](https://github.com/letta-ai/letta) | Stateful AI agent framework with multi-tier memory system — discovering it prompted refinements to this stack's memory pipeline |

## Contact

- **Discussions:** [GitHub Discussions](https://github.com/TadMSTR/homelab-agent/discussions) — questions, ideas, and show-and-tell
- **Email:** TadMSTR@pm.me
- **Issues:** [GitHub Issues](https://github.com/TadMSTR/homelab-agent/issues) — bugs and doc errors

## License

MIT
