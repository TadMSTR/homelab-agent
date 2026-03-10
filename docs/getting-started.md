# Getting Started

This guide walks through the homelab-agent stack in dependency order — what needs to exist before the next thing can work. You don't need to build the whole thing. Each section ends at a natural stopping point where you have something useful.

Read the [main README](../README.md) first for the architecture overview and origin story. This doc is the practical "what do I set up, in what order" companion.

## What You Need Before Anything

A Linux machine. Doesn't have to be dedicated — a VM, a spare desktop, or a mini PC all work. The full stack with all Docker containers runs comfortably on 16GB RAM; 32GB if you plan to run local LLMs via Ollama alongside everything else.

Install the basics: Docker CE + Compose, Node.js 20+, Python 3.11+, git. If you're reading this repo, you probably have most of these already.

## Layer 1: Claude Desktop + MCP Servers

**Time to value: 30 minutes.**

This is the foundation and the highest-ROI starting point. A Claude Pro or Max subscription gets you Claude Desktop, which supports MCP server integrations.

### Step 1: Install Claude Desktop

Download from [claude.ai](https://claude.ai) and install. On Linux, this means the `.deb` package (Debian/Ubuntu) or AppImage. Launch it, sign in.

### Step 2: Add Your First MCP Servers

Edit `~/.config/Claude/claude_desktop_config.json` and add MCP server entries. Start with these two — they're the minimum viable setup:

```json
{
  "mcpServers": {
    "desktop-commander": {
      "command": "npx",
      "args": ["-y", "@anthropic/desktop-commander"]
    },
    "basic-memory": {
      "command": "uvx",
      "args": ["basic-memory", "mcp"],
      "env": {
        "BASIC_MEMORY_PROJECT": "my-homelab"
      }
    }
  }
}
```

Desktop Commander gives Claude filesystem and terminal access. basic-memory gives it persistent notes between sessions. Restart Claude Desktop after editing the config.

See [`mcp-servers/README.md`](../mcp-servers/README.md) for the full list of available MCP servers and a prioritized adoption path. Add monitoring (Netdata, Grafana) and infrastructure access (Unraid, TrueNAS) based on what you run.

### Stopping Point #1

You now have Claude Desktop with direct access to your filesystem and persistent memory. This alone is a significant upgrade over browser-based Claude. You can manage files, run commands, and build up a knowledge base — all from natural conversation.

## Layer 2: Self-Hosted Services

**Time to value: 1-2 hours for the core stack.**

Layer 2 is Docker containers providing web-accessible AI tools. The dependency chain matters here — deploy in this order.

### Version Control Your Compose Files

Before you deploy anything: put your Docker compose files in a git repo. This is not optional advice — it's the single most important operational practice when AI agents have filesystem access.

When Claude has Desktop Commander or Claude Code access, it can and will edit your compose files directly. That's the point — you want it to be able to add environment variables, adjust port mappings, add containers. But an AI editing live config files without version control is how you end up debugging a broken stack at midnight with no idea what changed.

```bash
mkdir ~/docker && cd ~/docker && git init
```

Every compose file, every `.env` file (use `.env.example` with placeholders in git, real values in `.gitignore`'d `.env`), every proxy conf. Commit before and after AI-assisted changes. If something breaks, `git diff` tells you exactly what happened and `git checkout` gets you back. This has saved me more than once.

### Step 3: SWAG (Reverse Proxy)

Deploy SWAG first. It handles SSL termination and subdomain routing for everything that follows. You'll need a domain name and DNS validation credentials (Cloudflare is what this setup uses, but SWAG supports many providers).

See [`docs/components/swag.md`](components/swag.md) and [`docker/swag/`](../docker/swag/) for the compose file and configuration guide.

### Step 4: Authelia (SSO)

Deploy Authelia next. It provides single sign-on for all services behind SWAG. SWAG has first-class Authelia support — two lines uncommented per proxy conf file.

See [`docs/components/authelia.md`](components/authelia.md) and [`docker/authelia/`](../docker/authelia/) for setup.

### Stopping Point #2

SWAG + Authelia gives you a reverse proxy with SSO protecting all your `*.yourdomain` services. Every service you add from here forward gets SSL and authentication automatically.

### Step 5: Pick Your Services

The remaining Layer 2 services are independent of each other. Deploy whichever ones solve a problem you have:

**LibreChat** — if you want a web-based multi-provider chat UI with agents, MCP tool access, and memory. This is the most feature-rich option and the primary interactive interface beyond Claude Desktop. See [`docs/components/librechat.md`](components/librechat.md).

**SearXNG** — if you want self-hosted private search and the LibreChat web search pipeline. SearXNG is also the search backend for LibreChat's research agent. See [`docs/components/searxng.md`](components/searxng.md).

**Dockhand** — if you want a visual Docker stack manager. Lightweight, single container. See [`docs/components/dockhand.md`](components/dockhand.md).

**Open Notebook** — if you want an AI research and document analysis tool. See [`docs/components/open-notebook.md`](components/open-notebook.md).

**qmd (HTTP mode)** — if you want semantic search available to LibreChat and other web clients. qmd runs as a PM2 service on the host (not a Docker container). See [`docs/components/qmd.md`](components/qmd.md).

### Stopping Point #3

You now have a full self-hosted AI service stack accessible from any browser, protected by SSO. Household members or team members can use LibreChat and other tools without needing Claude Desktop access.

## Layer 3: Multi-Agent Claude Code Engine

**Time to value: 30 minutes for basics, ongoing for the full system.**

Layer 3 is the most opinionated part of the stack. It requires Claude Code (the CLI tool) and builds a persistent context and memory system on top of it.

### Step 6: Create Your CLAUDE.md Hierarchy

Start with a root CLAUDE.md at `~/.claude/CLAUDE.md`. This loads for every Claude Code session and should contain your infrastructure overview, key paths, and global conventions. See [`claude-code/CLAUDE.md.example`](../claude-code/CLAUDE.md.example) for a template.

Add project-specific CLAUDE.md files as needed. Start with one agent — the homelab-ops agent is a good first choice if you're primarily doing infrastructure work. See [`claude-code/projects/`](../claude-code/projects/) for examples.

### Step 7: Set Up Memory Directories

Create the scoped memory structure:

```bash
mkdir -p ~/.claude/memory/shared
mkdir -p ~/.claude/memory/agents/homelab-ops
# Add more agent directories as you create projects
```

Add instructions in your CLAUDE.md files for agents to write session summaries to their memory directories. The quality of the memory system depends entirely on what agents write here.

### Stopping Point #4

You have Claude Code with structured context and scoped memory. This is already a major improvement over bare Claude Code — the agent knows your infrastructure and accumulates learnings over time, even without the automated tooling below.

### Step 8: Add memsearch

Install memsearch to get automatic memory recall in Claude Code sessions:

```bash
pip install memsearch
```

Configure it to index your memory directories (see [`docs/components/memsearch.md`](components/memsearch.md)) and run `memsearch index`. The Claude Code plugin activates automatically and starts injecting relevant memories at session start.

### Step 9: Add PM2 Background Agents

Install PM2 (`npm install -g pm2`) and deploy the ecosystem config. Start with the essentials:

- **qmd** (always-on) — semantic search HTTP service
- **qmd-reindex** (daily cron) — keeps the search index fresh
- **resource-monitor** (periodic) — health checks with push notifications

Add memory-sync and other cron jobs as your usage matures. See [`pm2/ecosystem.config.js.example`](../pm2/ecosystem.config.js.example) for all available service definitions.

### Stopping Point #5 (Full Stack)

You have the complete system: Claude Desktop with MCP tools, a self-hosted service stack, and a multi-agent Claude Code engine with persistent memory that improves over time. The memory sync agent handles knowledge curation automatically. New sessions start with context from past sessions. Semantic search covers your entire documentation and memory corpus.

## What's Not Covered Here

This guide covers setup order and stopping points. For detailed configuration of each component, see the individual component docs in [`docs/components/`](components/). For Docker compose files, see [`docker/`](../docker/). For MCP server config patterns, see [`mcp-servers/README.md`](../mcp-servers/README.md).

Guacamole (remote desktop access) is mentioned in the architecture but not covered here — it's standard setup and well-documented upstream. NFS backup configuration is environment-specific and covered in the PM2 ecosystem config comments.

---

## Related Docs

- [Architecture overview](../README.md#architecture) — the three-layer model this guide follows
- [MCP servers reference](../mcp-servers/README.md) — detailed config patterns and adoption path
- [PM2 ecosystem config](../pm2/ecosystem.config.js.example) — service and cron definitions
- [Component docs](components/) — per-component deep dives
