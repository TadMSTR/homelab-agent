<p align="center">
  <img src="docs/assets/banner.png" alt="homelab-agent banner" />
</p>

# homelab-agent

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-enabled-blueviolet)](https://claude.ai/code)

This repo documents how I run Claude as an always-on infrastructure assistant across my homelab — with persistent context, live tool access to my hosts, and a self-hosted service stack to support it. Modular by design: take the whole thing or just the parts that fit your setup.

## Recent Updates

- **2026-03-14** — Doc-health agent: weekly automated documentation audit (drift, index, coverage, staleness, sanitization) with Opus model
- **2026-03-14** — Component docs for homelab-ops MCP, diag-check, and doc-health
- **2026-03-14** — Build plan handoff workflow: research agents design plans, implementation agents pick them up on session start
- **2026-03-13** — 3-tier memory system with automated nightly consolidation (session → working → distilled)
- **2026-03-12** — Agent panel component doc: claudebox-panel with health monitoring, PM2 management, diagnostics, and file browser

## Contents

- [How This Started](#how-this-started)
- [Architecture](#architecture)
  - [Layer 1 — Host & Core Tooling](#layer-1--host--core-tooling)
  - [Layer 2 — Self-Hosted Service Stack](#layer-2--self-hosted-service-stack)
  - [Layer 3 — Multi-Agent Claude Code Engine](#layer-3--multi-agent-claude-code-engine)
- [The Memory / Context System](#the-memory--context-system)
- [What Makes This Different](#what-makes-this-different)
- [Prerequisites](#prerequisites)
- [Repo Structure](#repo-structure)
- [Related Repos](#related-repos)

## How This Started

I watched a TechnoTim video on TrueNAS and Docker, needed a backup script, and used Claude to write it. The script worked, but Claude kept asking me the same questions about my setup every session. So I started writing down my infrastructure in markdown files and feeding them as context. That context system grew into a structured repository — profiles, preferences, infrastructure docs, project instructions — which I started calling the "prime directive."

Once Claude had persistent context about my environment, the interactions changed. Instead of explaining my setup every time, I could say "check if the Plex container is healthy on unraid" and it already knew unraid's IP, what monitoring tools were available, and how my Docker stacks were organized. That was the inflection point.

I built a dedicated mini PC (claudebox) to run Claude Desktop full-time with Model Context Protocol (MCP) tool integrations — direct access to Netdata, Grafana, GitHub, the filesystem, and a browser. Then I layered on a self-hosted service stack: reverse proxy with SSO, a multi-provider chat UI, semantic search over all my docs and repos, and a Claude Code web interface. On top of that, a multi-agent Claude Code engine with scoped memory, background jobs, and automated knowledge sync.

It grew organically from "AI writes me a script" to "AI operates alongside me as infrastructure."

## Architecture

The system has three layers. Each is independently useful — you don't need all three.

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Multi-Agent Claude Code Engine                │
│  CLAUDE.md hierarchy · scoped memory · memsearch        │
│  PM2 background agents · automated memory sync          │
├─────────────────────────────────────────────────────────┤
│  Layer 2: Self-Hosted Service Stack (Docker)            │
│  SWAG/Authelia · LibreChat · qmd · CloudCLI · SearXNG   │
│  Dockhand · Open Notebook                               │
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
| Fluxer | Chat bot gateway + MCP tools for the Fluxer platform (shelved) | me |
| GitHub | Repo management, issues, PRs, code search across multiple accounts | Anthropic |
| Grafana | Dashboard management, alert rules, Loki log queries, InfluxDB metrics | Grafana |
| homelab-ops | Shell, file, and process operations over HTTP (Claude Code + LibreChat) | me |
| InfluxDB | Time-series queries and writes for Telegraf-shipped metrics | community |
| jobsearch-mcp | Multi-board job search, resume scoring, application tracking (LibreChat) | me |
| memsearch | Memory recall from past Claude Code sessions (plugin, not MCP) | community |
| Netdata | Real-time metrics from any monitored host (CPU, RAM, disk, containers, alerts) | Netdata |
| Playwright | Browser automation — navigate, click, fill forms, take screenshots | Anthropic |
| qmd | Semantic search over repos, docs, and agent memory — stdio and HTTP modes | community |
| SearXNG | Private web search via self-hosted SearXNG — no API costs | me |
| TrueNAS | Datasets, pools, snapshots, users, SMB/NFS/iSCSI via REST API | community |
| Unraid | Array status, disk health, Docker containers, shares via GraphQL API | me |

For config patterns, standalone value ratings, and a prioritized adoption path, see [`mcp-servers/README.md`](mcp-servers/README.md).

**Guacamole** provides browser-based remote desktop access to the machine. Useful when you're away from the desk but need to interact with Claude Desktop's GUI.

**Standalone value:** Even without Layers 2 and 3, a dedicated machine running Claude Desktop with MCP servers is a significant upgrade over using Claude in a browser tab. The MCP integrations alone — being able to say "check disk health on unraid" or "query Grafana for the last hour of CPU on atlas" — change how you interact with your infrastructure.

### Layer 2 — Self-Hosted Service Stack

Docker containers on the same host, fronted by a reverse proxy with SSO. These provide web-accessible AI tools for the whole household or team, not just whoever is sitting at the Claude Desktop session.

| Service | What It Does | Why It's Here |
|---------|-------------|---------------|
| **Authelia** | SSO authentication gateway | One login for all services. SWAG has first-class Authelia support — two lines uncommented per proxy conf. |
| **CloudCLI** | Claude Code browser UI | Browser-based Claude Code interface with file explorer, multi-session tabs, and push notifications. Primary day-to-day interface for infrastructure work. |
| **Dockhand** | Docker stack manager UI | Visual management of Docker Compose stacks. |
| **LibreChat** | Multi-provider chat UI (Anthropic, OpenAI, Ollama, etc.) | Web-based chat with agent support, MCP tool integration, built-in memory, and RAG. The primary interface for interactive agent work. |
| **Open Notebook** | AI research/notebook tool | Document analysis and research with SurrealDB backend. |
| **SearXNG** | Private meta-search | Self-hosted search backend. Aggregates results from multiple engines with no API keys or per-query costs. Powers LibreChat's web search pipeline. |
| **qmd** | Semantic search MCP server | Hybrid search (BM25 + vector + LLM reranking) over all repos, docs, and agent memory. Local embeddings via GGUF models, GPU-accelerated on AMD iGPU via Vulkan. |
| **SWAG** | Nginx reverse proxy with Let's Encrypt wildcard SSL | Single entry point for all `*.yourdomain` services. DNS validation via Cloudflare — internal-only domain, no ports exposed to the internet. |

All containers share a single Docker network. SWAG handles SSL termination and routes `chat.yourdomain`, `auth.yourdomain`, `cloudcli.yourdomain`, etc. to the appropriate container. Authelia sits in front of everything — one-factor auth with a file-based user backend (sufficient for a single-user or household setup).

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

**memsearch** provides semantic search over the memory directories using local sentence-transformer embeddings and a vector database. The Claude Code plugin auto-injects relevant memories at session start and on each prompt. No API keys, no cloud services — runs entirely on the local CPU. See [`docs/components/memsearch.md`](docs/components/memsearch.md) for configuration details.

**PM2 Background Agents:**

| Service | Schedule | What It Does |
|---------|----------|-------------|
| docker-stack-backup | 1:00 AM daily | Stops containers, rsyncs appdata to NFS, restarts |
| memory-sync | 4:00 AM daily | Exports LibreChat memory, reads Claude Code memory files, distills durable knowledge into the context repo |
| qmd-reindex | 5:00 AM daily | Pulls latest from all git repos, re-embeds for semantic search |
| resource-monitor | Every 6 hours | Checks RAM, disk, Docker health, PM2 status, NFS mounts; alerts via ntfy |
| dep-update-check | Wednesdays noon | Checks for updates to pinned dependencies (qmd, Authelia, Claude Code) |

See [`pm2/ecosystem.config.js.example`](pm2/ecosystem.config.js.example) for full configuration including an optional upstream issue watcher.

**Standalone value:** The CLAUDE.md hierarchy alone is worth adopting. Even without memsearch or the background agents, giving Claude Code structured context about your infrastructure dramatically improves the quality of its responses. Start with a root CLAUDE.md and one project, expand from there.

## The Memory / Context System

This is the connective tissue that makes the whole thing more than the sum of its parts. Most people's experience with AI assistants is stateless — every conversation starts from zero. This system has four layers of persistent context:

1. **Prime directive repo** — Stable configuration: infrastructure docs, project instructions, profile/preferences, deployment scripts. Loaded at session start via CLAUDE.md references and qmd search. This is the source of truth.

2. **basic-memory** — Working notes between commits. Obsidian-compatible markdown files managed via MCP. Good for capturing things mid-session that aren't ready for the prime directive yet.

3. **Per-agent CLAUDE.md memory files** — Session summaries and learnings written by agents during their work. Indexed by memsearch for auto-recall in future sessions.

4. **Automated nightly memory sync** — A headless Claude Code agent runs at 4 AM, reads recent memory from both Claude Code sessions (memsearch) and LibreChat conversations (MongoDB export), and distills durable knowledge back into the prime directive repo. Knowledge accumulates without manual curation.

The result: when I start a session on Monday, the agent already knows about the Docker stack change I made on Friday, the monitoring alert from Saturday, and the research I did on Sunday. It knows because the memory sync agent captured those events and the semantic search surfaced them as relevant context.

## What Makes This Different

Most AI homelab setups are "I use ChatGPT to write scripts." This is a persistent, context-aware system where the AI knows the infrastructure, remembers decisions, and improves over time.

The key differences:

**Persistent context, not copy-paste.** The AI doesn't need you to explain your setup every session. It loads infrastructure docs, reads recent memory, and picks up where you left off.

**Multi-agent with scoped memory.** Different agents handle different domains without context bleed. The homelab-ops agent knows about Docker and monitoring. The dev agent knows about git workflows and code standards. They share infrastructure knowledge but keep domain-specific learnings separate.

**Automated knowledge accumulation.** The memory sync agent means you don't have to manually maintain documentation. Durable decisions and learnings flow from work sessions into the persistent knowledge base automatically.

**Tool access, not just chat.** Via MCP, the AI can directly query Netdata metrics, check Grafana dashboards, search GitHub repos, read and write files, and automate browser tasks. It's not just answering questions — it's operating.

**Version-controlled infrastructure.** When AI agents have filesystem access, they will edit your config files directly — compose files, `.env` files, proxy confs. This is powerful, but it means you need version control on everything the AI can touch. All Docker compose files in this setup live in a git repo. Every change is tracked, diffable, and reversible. If an agent makes a bad edit, `git diff` shows what happened and `git checkout` recovers it. This isn't optional — it's the safety net that makes AI-assisted infrastructure management viable.

**Model-agnostic in practice.** The core engine runs on Claude, but LibreChat supports any provider (OpenAI, Ollama, etc.). SearXNG provides self-hosted search without API keys. The architecture doesn't lock you into a single vendor.

## Prerequisites

To run the full stack, you need:

- A dedicated machine (mini PC, old desktop, VM — 16GB+ RAM recommended, 32GB if running local models via Ollama)
- Debian/Ubuntu (or any Linux with Docker support)
- Docker CE + Compose
- Node.js 20+ and npm (for qmd, cui, MCP servers)
- Python 3.11+ (for memsearch)
- A [Claude Pro or Max subscription](https://claude.ai) (for Claude Desktop + Claude Code)
- An Anthropic API key (for LibreChat)
- A domain name (for SWAG SSL — can be internal-only with DNS validation via Cloudflare)
- Optional: NFS server for backups (TrueNAS, Unraid, or any NFS-capable host)

You don't need all of this to get value. See the component breakdown above for what each piece requires independently.

## Repo Structure

> **AI agents:** See [`index.md`](index.md) for a machine-readable navigation index — load only the context relevant to your current task.

```
homelab-agent/
├── README.md                        ← You are here
├── index.md                         ← Agent navigation index (scoped context loading)
├── docs/
│   ├── architecture.md              ← Detailed system architecture and data flows
│   ├── getting-started.md           ← Setup overview and prerequisites
│   └── components/                  ← Per-component deep dives
│       ├── swag.md                  ← Reverse proxy, Cloudflare DNS, proxy conf pattern
│       ├── authelia.md              ← SSO config, file-based user backend, SWAG integration
│       ├── librechat.md             ← Setup, web search pipeline, reranker wrapper, gotchas
│       ├── searxng.md               ← SearXNG + Valkey, shared search backend
│       ├── dockhand.md              ← Docker socket access, multi-host stack visibility
│       ├── open-notebook.md         ← SurrealDB, dual-port proxy config
│       ├── qmd.md                   ← Semantic search, dual transport, GPU acceleration
│       ├── memsearch.md             ← Memory recall for Claude Code, plugin integration
│       ├── memory-sync.md           ← Knowledge distillation pipeline, PM2 cron
│       └── backups.md               ← Backrest/restic, Claude backup, Docker appdata backup
├── claude-code/
│   ├── CLAUDE.md.example            ← Root CLAUDE.md template
│   └── projects/                    ← Per-agent CLAUDE.md examples
│       ├── homelab-ops.md           ← Infrastructure management agent
│       ├── dev.md                   ← Development agent
│       ├── research.md              ← Research agent
│       └── memory-sync.md           ← Memory distillation agent
├── docker/
│   ├── swag/
│   │   └── docker-compose.yml       ← Reverse proxy + wildcard SSL
│   ├── authelia/
│   │   └── docker-compose.yml       ← SSO authentication gateway
│   ├── librechat/
│   │   ├── docker-compose.yml       ← Multi-provider chat + MongoDB + Meilisearch
│   │   └── librechat.yaml.example   ← LibreChat config with web search and MCP
│   ├── firecrawl-simple/
│   │   └── docker-compose.yml       ← Web scraper for LibreChat search pipeline
│   ├── reranker/
│   │   ├── docker-compose.yml       ← Jina-compatible reranker wrapper
│   │   ├── Dockerfile               ← FlashRank + FastAPI build
│   │   └── main.py                  ← Reranker API source (~115 lines)
│   ├── searxng/
│   │   └── docker-compose.yml       ← SearXNG + Valkey
│   ├── dockhand/
│   │   └── docker-compose.yml       ← Docker stack manager UI
│   └── open-notebook/
│       └── docker-compose.yml       ← AI notebook + SurrealDB
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

| Repo | Description |
|------|-------------|
| [TadMSTR/backrest-mcp-server](https://github.com/TadMSTR/backrest-mcp-server) | Backrest MCP server — trigger backups and query operation history via Backrest's API |
| [TadMSTR/bsky-mcp-server](https://github.com/TadMSTR/bsky-mcp-server) | Bluesky MCP server (personal fork) — AT Protocol integration for Claude |
| [TadMSTR/unraid-mcp-server](https://github.com/TadMSTR/unraid-mcp-server) | Unraid MCP server — array status, disk health, Docker, shares via GraphQL |
| [tobi/qmd](https://github.com/tobi/qmd) | Semantic search engine with MCP server mode — hybrid BM25 + vector + LLM reranking |
| [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) | CloudCLI — Claude Code browser UI with file explorer, multi-session tabs, and notifications |
| [wbopan/cui](https://github.com/wbopan/cui) | CUI — Claude Code web UI with browser-based terminal sessions |
| [danny-avila/LibreChat](https://github.com/danny-avila/LibreChat) | Multi-provider chat interface with agents, MCP, memory, and RAG |

## License

MIT

