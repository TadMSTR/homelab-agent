# MCP Servers

MCP (Model Context Protocol) is what gives Claude direct tool access to your
infrastructure. Instead of copy-pasting command output into a chat window, Claude
makes structured tool calls — query metrics, check disk health, search repos,
manage files — all within the conversation.

This document covers the MCP servers used in this setup, how they're configured,
and what each one does.

## How MCP Works with Claude Desktop

Claude Desktop loads MCP servers from its config file:

```
~/.config/Claude/claude_desktop_config.json
```

Each server entry specifies a command to run and optional environment variables.
Claude Desktop launches each server as a subprocess using stdio transport. The
server exposes tools that Claude can call during conversations.

## MCP Servers in This Stack

### Netdata

**Purpose:** Real-time system metrics from any Netdata-monitored host — CPU, RAM,
disk, network, container stats, active alerts, and anomaly detection.

**Package:** `nd-mcp` (Netdata's official MCP binary)

**Why it's here:** Gives Claude direct access to monitoring data without you
needing to open a dashboard. "Is CPU high on the storage server?" gets answered
from live metrics, not your memory.

**Config pattern (one entry per monitored host):**
```json
{
  "netdata-hostname": {
    "command": "/usr/sbin/nd-mcp",
    "args": ["ws://HOST_IP:19999/mcp"]
  }
}
```

For hosts requiring authentication, pass a bearer token:
```json
{
  "netdata-hostname": {
    "command": "/usr/sbin/nd-mcp",
    "args": ["--bearer", "YOUR_TOKEN", "ws://HOST_IP:19999/mcp"]
  }
}
```

**Get the token:** `docker exec -it netdata cat /var/lib/netdata/mcp_dev_preview_api_key`

**Standalone value:** High. Even without the rest of this stack, Netdata MCP
on its own turns Claude into a monitoring assistant.

---

### Grafana

**Purpose:** Dashboard management, alert rules, Loki log queries, InfluxDB/Prometheus
metric queries, incident management, OnCall schedules.

**Transport:** Remote MCP server (Grafana Cloud or self-hosted with MCP endpoint)

**Why it's here:** Complements Netdata with historical data, dashboards, and
structured alerting. Netdata is real-time; Grafana is trends and investigation.

**Note:** Available as a Claude.ai connector or via the Grafana MCP server.
Configuration depends on your Grafana deployment.

---

### GitHub

**Purpose:** Repo management, issues, PRs, code search, file contents.

**Transport:** Claude.ai built-in connector (or via `@modelcontextprotocol/server-github`)

**Why it's here:** Claude can search your repos, read code, create issues, and
review PRs without you switching to a browser.

**Important — use your shell MCP for local git, not this.** GitHub MCP is for
remote operations that require the GitHub API: opening issues, creating PRs,
reviewing code, reading files from repos you haven't checked out locally. For
anything involving a repo that already exists on disk — committing files, pushing,
running git log — use your shell/file MCP server instead. It's faster,
doesn't require API calls, and works exactly as you'd expect from the terminal.
Claude left to its own devices will reach for GitHub MCP for local git operations;
nudging it toward your shell tools in CLAUDE.md or agent instructions avoids
unnecessary API round-trips and the confusion of mixing local and remote tool use.

**Tip:** If you have multiple GitHub accounts (personal + work), configure
separate MCP server entries with different SSH keys or tokens. Label them
clearly (`github-personal`, `github-work`) so Claude knows which to use.

---

### Desktop Commander

**Purpose:** Filesystem operations, terminal commands, process management on the
host machine.

**Package:** `@anthropic/desktop-commander` (npm)

**Why it's here:** Claude Desktop's stdio transport works fine with Desktop
Commander, and it covers the basics well: file reads/writes, shell commands,
process management. I still use it in Claude Desktop for day-to-day work.

**Config pattern:**
```json
{
  "desktop-commander": {
    "command": "npx",
    "args": ["-y", "@anthropic/desktop-commander"]
  }
}
```

**Standalone value:** High. If you only use Claude Desktop (not Claude Code or
LibreChat), this is all you need for filesystem and shell access.

---

### homelab-ops

**Purpose:** Filesystem operations, shell commands, file editing, process
inspection on the host machine — over HTTP.

**Built by:** me — a FastMCP (Python) server purpose-built for homelab operations.

**GitHub:** https://github.com/TadMSTR/homelab-agent (see `mcp-servers/` notes)

**Why it's here:** Desktop Commander works great for Claude Desktop, but Claude
Code and LibreChat agents need HTTP transport — stdio doesn't work when the
client isn't launching the server as a subprocess. I built homelab-ops to expose
exactly the tools I need as a shared HTTP service. Multiple clients connect to
the same running instance. I primarily use Claude Code via CloudCLI now, so
homelab-ops handles most of my day-to-day infrastructure work.

**Tools:**

| Tool | Description |
|------|-------------|
| `run_command` | Execute a shell command, returns stdout/stderr/exit_code |
| `read_file` | Read a file by path, optional line range |
| `write_file` | Write or overwrite a file, creates parent dirs |
| `edit_file` | Find-and-replace edit (old_str must match exactly once) |
| `read_directory` | List directory contents, optional recursive with depth limit |
| `list_processes` | List running processes sorted by cpu/mem/pid |

**Transport:** Streamable-HTTP on port 8282, managed by PM2. Claude Code connects
directly; LibreChat containers reach it via `host.docker.internal`.

**Config pattern (`~/.claude.json`):**
```json
{
  "homelab-ops": {
    "type": "http",
    "url": "http://localhost:8282/mcp"
  }
}
```

**Standalone value:** Essential. This is the minimum viable MCP server for
infrastructure work. The HTTP transport means multiple clients can share it
without fighting over a stdio subprocess.
---

### helm-ops-mcp

**Purpose:** Same tool surface as homelab-ops (`run_command`, `read_file`, `write_file`, `edit_file`, `read_directory`, `upload_file`) — but targeted at a remote build host over SSH instead of the local machine.

**Built by:** me — FastMCP (Python) server, runs on claudebox and tunnels operations to the second build machine via SSH.

**Why it's here:** Building a second platform (in my case, the Helm forge) on a separate mini PC means the build agent on claudebox needs to operate on a remote host as if it were local. helm-ops makes that transparent — the agent calls the same tool names regardless of which host it's targeting. A small set of `local_*` read-only tools also gives the build agent access to build plans, design docs, and memory on claudebox without a second connection.

**Tools (remote, via SSH):** `run_command`, `read_file`, `write_file`, `edit_file`, `read_directory`, `upload_file` (SCP from claudebox to remote).

**Tools (local, claudebox, read-only):** `local_read_file`, `local_read_directory`. Restricted to an allowlist: build plans, design docs, memory, and the prime-directive repo.

**Transport:** Streamable-HTTP on `127.0.0.1:8283`, managed by PM2. SSH backend uses key-based auth from claudebox to the remote host.

**Config pattern (`~/.claude.json`):**
```json
{
  "helm-ops": {
    "type": "http",
    "url": "http://localhost:8283/mcp"
  }
}
```

Environment variables on the PM2 service: `HELM_SSH_HOST` (required), `HELM_SSH_USER` (default `ted`), `HELM_SSH_KEY` (default `~/.ssh/id_ed25519`), `HELM_SSH_PORT` (default 22), `HELM_SSH_TIMEOUT` (default 60s).

**Security:** Unrestricted shell access on the remote host. Designed for trusted internal use — do not expose port 8283 externally.

**Standalone value:** Niche. Only relevant if you have a second machine you want a Claude Code agent to operate on as if it were local. For single-host setups, homelab-ops alone is sufficient.

---

### pm2-mcp

**Purpose:** Structured read and limited write access to PM2 services — list processes, get details, tail logs, restart, stop, start.

**Built by:** me — FastMCP (Python) server that speaks directly to `pm2 jlist` rather than parsing human-readable output.

**GitHub:** https://github.com/TadMSTR/pm2-mcp

**Why it's here:** Shell-level PM2 inspection via homelab-ops works, but it means parsing `pm2 status` output or writing ad-hoc jq. pm2-mcp returns typed fields from `pm2 jlist` directly, validates service names before any write operation, and runs as a localhost-only HTTP service managed by PM2 itself.

**Tools:**

| Tool | Description |
|------|-------------|
| `list_services` | List all PM2 services with status, PID, CPU, and memory. Optional `status_filter`: `"online"`, `"stopped"`, or `"errored"`. |
| `get_service` | Full detail for one service — script path, cwd, args, log paths, created_at. |
| `get_logs` | Tail recent log output. Defaults: 50 lines, errors included. |
| `restart_service` | Restart a service. Validates name first — returns `{ok: false}` if not found. |
| `stop_service` | Stop a service without removing it from the PM2 process list. |
| `start_service` | Resume a stopped service already registered in PM2. |

**Transport:** Streamable-HTTP on `127.0.0.1:8486`, managed by PM2. Localhost-only — not exposed externally or to Docker networks.

**Config pattern (`~/.claude.json`):**
```json
{
  "pm2": {
    "type": "http",
    "url": "http://127.0.0.1:8486/mcp"
  }
}
```

**Security:** No authentication by default — localhost only. Write tools validate service names before acting. Don't proxy this externally.

**Standalone value:** Medium-high. If you manage services with PM2, this removes the need to shell out for process status. The read tools are safe for any agent; scope the write tools (restart/stop/start) to agents that actually need them.


---

### Playwright

**Purpose:** Browser automation — navigate pages, click buttons, fill forms,
take screenshots, read accessibility trees.

**Package:** `@anthropic/mcp-playwright` (npm)

**Why it's here:** Some tasks require a browser. Checking a web UI status page,
filling a form in a self-hosted app, taking a screenshot for documentation.
The accessibility tree snapshot is especially useful — Claude can "see" a page
structure without needing screenshots.

---

### basic-memory

**Purpose:** Persistent knowledge base as Obsidian-compatible markdown files.
Bidirectional read/write, traversable knowledge graph.

**Package:** `basic-memory` (Python, via `uvx`)

**Config pattern:**
```json
{
  "basic-memory": {
    "command": "uvx",
    "args": ["basic-memory", "mcp"],
    "env": {
      "BASIC_MEMORY_PROJECT": "your-project-name"
    }
  }
}
```

**Why it's here:** Working memory between sessions. Good for capturing things
mid-conversation that aren't ready for your main context repo yet. The Obsidian
compatibility means you can browse and edit the knowledge base outside of Claude.

**Standalone value:** High. Even without the rest of the stack, basic-memory
gives Claude persistent notes across conversations.

---

### qmd (Semantic Search)

**Purpose:** Hybrid search (BM25 + vector + LLM reranking) over repos, docs, and
agent memory. Local embeddings, no external API keys needed.

**Package:** `@tobilu/qmd` (npm)

**GitHub:** https://github.com/tobi/qmd

**Transports:**
- **stdio** (for Claude Desktop): `qmd mcp`
- **HTTP** (for LibreChat/other clients): `qmd mcp --http --port 8181`

**Config pattern:**
```json
{
  "qmd": {
    "command": "qmd",
    "args": ["mcp"]
  }
}
```

**Why it's here:** This is what makes the memory system searchable. qmd indexes
your context repo, agent memory files, compose files, and any other collections
you configure. When Claude needs to recall a past decision or find a config
pattern, qmd surfaces it via semantic search.

**GPU acceleration:** Supports Vulkan for AMD iGPUs and CUDA for Nvidia. Falls
back to CPU if no GPU available. GPU gives ~3.5x speedup on embedding generation.

**Standalone value:** Medium-high. Requires some content to index, but once you
have a context repo and some memory files, it's very powerful.

---

### graphiti-mcp

**Purpose:** Tool access to a temporal knowledge graph — add episodes, search nodes and facts, query relationships between infrastructure entities (services, hosts, networks, agents) stored in Neo4j via [Graphiti](https://github.com/getzep/graphiti).

**Package:** community — runs the upstream Graphiti library as a Streamable HTTP MCP server in a custom Docker image (`graphiti-mcp:local`).

**Why it's here:** File-based memory (qmd, memsearch) is good at narrative recall — "what did we decide about X?" The knowledge graph is good at relational recall — "what runs on atlas?", "what depends on SWAG?", "which services moved network in the last 30 days?" Both layers complement each other; agents query whichever fits the question.

**Tools:** `add_memory`, `search_memory_facts`, `search_nodes`, `get_episodes`, `get_entity_edge`, `delete_entity_edge`, `delete_episode`, `get_status`, `clear_graph`.

**Transport:** Streamable HTTP on `localhost:8000`. The container runs on a dedicated `graphiti-internal` Docker network (not on the shared agent network); agents connect via host loopback rather than Docker DNS.

**Config pattern (`~/.claude.json`):**
```json
{
  "graphiti": {
    "type": "http",
    "url": "http://localhost:8000/mcp"
  }
}
```

**How the graph is populated:** Most ingestion is automatic — `memory-flush` writes real-time events, and the nightly `memory-pipeline` batch ingests durable notes. Direct `add_memory` calls are reserved for infrastructure state changes (deploys, network topology, port remaps) that aren't already captured by the pipeline. See [graphiti.md](../docs/components/graphiti.md) for the full ingestion model and entity ontology.

**Standalone value:** Medium. The Neo4j + Graphiti stack is more involved to set up than a flat-file memory system, and the graph only earns its keep once you have a non-trivial number of entities and want to ask relational questions across them. For single-agent or small setups, qmd + a context repo is usually enough.

---

### InfluxDB

**Purpose:** Query and write time-series data. Pairs with Telegraf for host metrics.

**Package:** `influxdb-mcp-server` (npm, community package)

**GitHub:** https://github.com/idoru/influxdb-mcp-server

**Config pattern:**
```json
{
  "influxdb": {
    "command": "npx",
    "args": ["-y", "influxdb-mcp-server"],
    "env": {
      "INFLUXDB_URL": "http://YOUR_INFLUXDB_HOST:8086",
      "INFLUXDB_TOKEN": "YOUR_TOKEN",
      "INFLUXDB_ORG": "YOUR_ORG"
    }
  }
}
```

**Why it's here:** Historical metrics. Telegraf ships host metrics into per-host
InfluxDB buckets. Claude can query trends, compare time periods, and investigate
anomalies using Flux queries.

**Note:** The community package targets InfluxDB OSS v2 API. Make sure you use
the admin token, not the password — they're different values in the `.env` file
and easy to mix up.

---

### Unraid MCP

**Purpose:** Array status, disk health, parity history, Docker containers, shares,
notifications, system info — all via Unraid's GraphQL API.

**GitHub:** https://github.com/TadMSTR/unraid-mcp-server

**Config pattern:**
```json
{
  "unraid": {
    "command": "node",
    "args": ["/path/to/unraid-mcp-server/build/src/index.js"],
    "env": {
      "UNRAID_HOST": "https://YOUR_UNRAID_IP:4443",
      "UNRAID_API_KEY": "YOUR_API_KEY"
    }
  }
}
```

**Why it's here:** If you run Unraid, this gives Claude direct read access to
your array, disks, and containers. "Check if parity is running" or "what's the
disk health status" without opening the Unraid web UI.

**Note:** Use a viewer-role API key (read-only). No reason to give Claude write
access to your array.

---

### TrueNAS MCP

**Purpose:** Datasets, pools, snapshots, users, SMB/NFS/iSCSI management via
TrueNAS REST API.

**Package:** `truenas-mcp-server` (Python, via `uvx`)

**GitHub:** https://github.com/vespo92/TrueNasCoreMCP

**Config pattern:**
```json
{
  "truenas": {
    "command": "uvx",
    "args": ["truenas-mcp-server"],
    "env": {
      "TRUENAS_HOST": "https://YOUR_TRUENAS_IP:4443",
      "TRUENAS_API_KEY": "YOUR_API_KEY",
      "TRUENAS_VERIFY_SSL": "false"
    }
  }
}
```

**Note:** Self-signed TrueNAS certs require `TRUENAS_VERIFY_SSL=false`. The
package may have SSL bugs — check the repo issues if you hit connection errors.

---

### Bluesky MCP

**Purpose:** Social media management via AT Protocol — post, reply, follow,
search, manage feeds.

**GitHub:** https://github.com/TadMSTR/bsky-mcp-server (fork)

**Why it's here:** Optional. Useful if you maintain a public homelab presence
on Bluesky and want Claude to help manage it.

---

### Backrest

**Purpose:** Trigger backup plans and fetch operation history for
[Backrest](https://github.com/garethgeorge/backrest) — a web UI and
orchestrator for restic backups.

**GitHub:** https://github.com/TadMSTR/backrest-mcp-server

**Config pattern:**
```json
{
  "backrest": {
    "command": "node",
    "args": ["/path/to/backrest-mcp-server/build/src/index.js"],
    "env": {
      "BACKREST_URL": "http://YOUR_BACKREST_HOST:9898",
      "BACKREST_USERNAME": "YOUR_USERNAME",
      "BACKREST_PASSWORD": "YOUR_PASSWORD"
    }
  }
}
```

**Why it's here:** If you use Backrest for restic-based backups, this lets
Claude trigger backup plans and check operation history without opening the
Backrest web UI. "Run the home directory backup" or "did last night's backup
succeed?" from within a conversation.

**Note:** If Backrest auth is disabled, omit the username and password env vars.
Backrest uses a JSON-RPC HTTP gateway over gRPC — the MCP server handles the
protocol details.

**Standalone value:** Medium. Useful if you already run Backrest. Two tools —
`trigger-backup` and `get-operations` — focused and practical.

---

### SearXNG MCP

**Purpose:** Private web search for Claude Code — search the web and fetch page
content without sending queries through a commercial search API.

**Built by:** me — TypeScript MCP server wrapping a self-hosted SearXNG instance.

**Why it's here:** Claude Code doesn't have built-in web search. Rather than
paying for a search API or sending every query through Google, this connects to
three self-hosted services that together form a full search pipeline:

1. **SearXNG** — meta-search engine, aggregates results from multiple upstream engines
2. **Reranker** — a local ms-marco-MiniLM-L-12-v2 model that reranks search results by relevance to the query, so Claude sees the best matches first
3. **Firecrawl-simple** — scrapes full page content from URLs and returns clean markdown, used by `fetch_url` and `search_and_fetch`

Four tools: `search` (query with category/engine filters, results reranked),
`fetch_url` (scrape a URL, returns markdown), `search_and_fetch` (search + rerank +
fetch top results in one call), and `search_and_summarize` (search + fetch + Ollama
synthesis into a structured answer with sources).

The fetch pipeline uses a three-tier cascade: Firecrawl-simple → Crawl4AI → raw HTTP.
Each tier is skipped if unavailable, so `fetch_url` never fails silently.

**Prerequisites:** SearXNG (see [component doc](../docs/components/searxng.md)),
Firecrawl-simple (Trieve's lightweight fork), Crawl4AI, and a reranker service —
all running on the same Docker network (`claudebox-net`). Ollama is required for
`search_and_summarize` but optional otherwise.

**Config pattern (`~/.claude.json`):**
```json
{
  "searxng": {
    "type": "http",
    "url": "http://localhost:YOUR_PORT/mcp"
  }
}
```

**Standalone value:** High. If you self-host SearXNG, this gives any Claude Code
session private web search with zero API costs.

---

### matrix-mcp

**Purpose:** Send and receive Matrix messages, post artifacts, and enumerate joined rooms. Pairs with a self-hosted Synapse homeserver and per-agent Matrix accounts to create a persistent, threaded communications layer between operator and agents.

**Built by:** me — FastMCP (Python) server bundled with [`matrix-channel`](https://github.com/TadMSTR/matrix-channel), a Claude Code Channel plugin that injects operator replies as user input into the active session.

**GitHub:** https://github.com/TadMSTR/matrix-mcp

**Why it's here:** ntfy is fire-and-forget — no threading, no history, no two-way interaction. Matrix gives every agent a persistent room with full message history, the ability to post files and reports inline, and a way for the operator to reply back into a running session for permission relay. Element Web becomes a unified inbox for all agent activity, accessible from any device. ntfy is retained only for pending-approval and dead-letter notifications; everything else routes through Matrix.

**Tools:**

| Tool | Description |
|------|-------------|
| `send_matrix_message` | Send a text or markdown message to a room by short name (`dev`, `writer`, `claudebox`, etc.) |
| `post_artifact` | Upload a file from an allowlisted path and post a formatted link to the room |
| `get_matrix_messages` | Fetch recent messages from a room (used for reply polling and thread context) |
| `list_matrix_rooms` | Enumerate all rooms the bot account has joined |

**Transport:** Streamable-HTTP on `127.0.0.1:8487`, managed by PM2. Localhost only — Synapse handles all federation.

**Config pattern (`~/.claude.json`):**
```json
{
  "matrix": {
    "type": "http",
    "url": "http://127.0.0.1:8487/mcp"
  }
}
```

**Security:** Markdown bodies run through `bleach.clean()` with a Matrix-spec allowlist before being sent as `formatted_body` — disallowed tags are stripped, raw HTML cannot pass through. `post_artifact` is restricted to `~/repos/`, `~/.claude/comms/`, and `~/.claude/memory/` to prevent agents from posting Docker secrets or compose files. Per-agent accounts are provisioned by a companion `matrix-admin-bot` PM2 service via the Synapse admin API.

**Prerequisites:** A self-hosted Synapse homeserver (with PostgreSQL backend and Element Web for the operator UI) on the same Docker network. See [matrix.md](../docs/components/matrix.md) for the full stack — Synapse + PostgreSQL + Element Web + matrix-admin-bot.

**Standalone value:** High *if* you already run a Synapse homeserver or are willing to deploy one. The MCP tool itself is small, but it requires the full Matrix stack to be useful. For a single-agent setup, ntfy is simpler. For multi-agent setups where you want history and two-way interaction, this is the upgrade path.

---

### ntfy-mcp

**Purpose:** Send push notifications via ntfy from any Claude agent — no shell access required.

**Built by:** me — FastMCP (Python), stateless HTTP proxy between agents and an ntfy instance.

**GitHub:** https://github.com/TadMSTR/ntfy-mcp

**Why it's here:** Every automated workflow on claudebox already uses ntfy for push notifications (memory pipeline completions, backup results, agent alerts), but agents had to use `run_command` to fire curl. This gives every Claude Code and LibreChat session a native `send_notification` tool call.

**Tool:**

| Tool | Description |
|------|-------------|
| `send_notification` | Send a push notification with optional title, priority, tags, Markdown body, click URL, and icon. |

**Transport:** Streamable-HTTP, runs as a Docker container on port 8484. Claude Code connects via `localhost`; LibreChat containers via `host.docker.internal`.

**Config pattern (`~/.claude.json`):**
```json
{
  "ntfy": {
    "type": "http",
    "url": "http://127.0.0.1:8484/mcp"
  }
}
```

**Standalone value:** High. If you already run ntfy for push notifications, this is a 10-minute integration. Stateless — no database, nothing to maintain.


---

### Fluxer MCP

**Purpose:** Chat bot gateway + MCP tools for community interaction via the
Fluxer platform.

**Built by:** me — TypeScript, currently shelved.

**GitHub:** https://github.com/TadMSTR/fluxer-mcp-server

**Why it's here:** A work-in-progress. Fluxer is a chat platform, and this
server connects to its gateway to maintain a bot presence in a homelab
community. The MCP side exposes three tools (`get_bot_status`, `send_message`,
`get_messages`) for manual control from Claude Desktop, while the gateway
listener handles autonomous responses using Claude Haiku. Shelved for now —
the concept works but needs more polish.

**Standalone value:** Low. Niche use case, and the Fluxer platform itself is
still maturing.

---

### jobsearch-mcp

**Purpose:** Multi-board job search, resume scoring, and application tracking —
all from a LibreChat agent.

**Built by:** me — FastMCP (Python), designed for multi-user LibreChat deployments.

**GitHub:** https://github.com/TadMSTR/jobsearch-mcp

**Why it's here:** A personal project that turned into a good example of building
a non-trivial FastMCP server with Postgres persistence, local vector search (Qdrant +
Ollama bge-m3 embeddings), and per-user state in a multi-user LibreChat environment.
v2 added a Resume Profile system — agents can store a resume, extract structured criteria,
and score job listings against the profile using semantic similarity.

**Standalone value:** Medium. Useful if you're job hunting and want to aggregate
searches across Adzuna, Remotive, WeWorkRemotely, Jobicy, and LinkedIn from a
single interface. Requires Postgres, Qdrant, and Ollama (bge-m3 model) for semantic
matching and resume scoring. v1→v2 upgrade requires dropping and recreating the
Qdrant collection (embedding dimensions changed).

---

### memsearch (Claude Code Plugin)

**Purpose:** Memory recall for Claude Code — searches past session context,
decisions, and notes using local embeddings.

**Package:** `memsearch` (Python, via pip)

**Why it's here:** This isn't an MCP server — it's a Claude Code plugin that
gives the agent access to indexed memory from past sessions. It uses local
embeddings (no external API) and integrates directly into Claude Code's plugin
system. Mentioned here because it fills the same role as an MCP server: giving
Claude access to information it wouldn't otherwise have.

**Standalone value:** Medium. Most useful once you have a meaningful volume of
past sessions. Lightweight to set up — `pip install "memsearch[local]"` and
enable in Claude Code settings.

---

### scoped-mcp

**Purpose:** Per-agent MCP tool proxy. One server process per agent loads only the tool modules its manifest allows, enforces resource boundaries between agents, holds credentials so agents never see token values, and writes a structured audit log entry for every tool call.

**Built by:** me — Python, manifest-driven, middleware-based.

**Source:** [TadMSTR/scoped-mcp](https://github.com/TadMSTR/scoped-mcp) | **PyPI:** [`scoped-mcp`](https://pypi.org/project/scoped-mcp/)

**Why it's here:** Multi-agent setups that share MCP servers are dangerous by default. Every agent sees every tool. Agent A can read Agent B's files, write to Agent B's database, send alerts from Agent B's ntfy topic. Credentials are exposed to all agents. Audit logs are fragmented across servers. scoped-mcp solves this with a proxy layer in front of every backend MCP — each agent gets its own server process configured by a YAML manifest that declares which modules load, what scope (filesystem path, ntfy topic, SQL prefix) is in bounds, and which credentials inject. Agents never receive tokens; they receive tool results.

**Manifest example:**
```yaml
agent_type: research
modules:
  filesystem:
    mode: read
    config:
      base_path: /data/agents
  ntfy:
    config:
      topic: "research-{agent_id}"
      max_priority: high
credentials:
  source: env  # or file, or vault
rate_limits:
  global: 60/minute
  per_tool:
    filesystem_write_file: 10/minute
hitl:
  approval_required: ["filesystem_delete_*", "sqlite_execute"]
  timeout_seconds: 300
```

**Hardening features (v1.0):** sliding-window rate limits with optional Dragonfly state backend, Vault credential source, regex/JSON-decoded argument filtering on inbound tool args, and human-in-the-loop approval for destructive operations.

**Transport:** stdio per agent process. The agent launches its scoped-mcp instance with `AGENT_ID` and `AGENT_TYPE` set; scoped-mcp loads the manifest matching the agent type.

**Standalone value:** High for any setup with two or more agents that share infrastructure. For a single-agent setup, the indirection isn't worth it — connect agents directly to backend MCPs.

See [scoped-mcp.md](../docs/components/scoped-mcp.md) for the full module surface, middleware protocol, and integration patterns.

---

### task-queue-mcp

**Purpose:** Schema-validated MCP access to the agent task queue. Replaces raw YAML file writes against `~/.claude/task-queue/` with type-checked tools (`submit_task`, `list_tasks`, `get_task`, `update_task`) that enforce the schema and transition rules the dispatcher expects.

**Built by:** me — FastMCP (Python), runs as a Docker container.

**Why it's here:** Agents that interact with the task queue via raw file I/O are fragile. The YAML schema has constraints — UUID4 format for IDs, enumerated status values, absolute paths in `context_refs`, append-only history — that are easy to violate when writing directly. A malformed task file silently fails or triggers spurious dispatcher errors. task-queue-mcp centralizes validation and transition rules at the tool boundary so the dispatcher reads files it can trust.

**Tools:**

| Tool | Description |
|------|-------------|
| `submit_task` | Create a new task YAML in `~/.claude/task-queue/` with `status: submitted`. Generates UUID4 and `created` timestamp automatically. |
| `list_tasks` | List tasks, optionally filtered by status or target agent. TTL-expired terminal tasks are excluded from results (but not deleted). |
| `get_task` | Retrieve a single task by full UUID. |
| `update_task` | Transition a task's status and append a history entry. Rejects illegal transitions without modifying the file. |

`pending-approval → approved` is intentionally not exposed — approval is a human action handled by the `task-approve` CLI.

**Transport:** Streamable-HTTP on `127.0.0.1:8485`, runs as a Docker container managed by PM2. The container is read-only with `cap_drop: ALL`, `no-new-privileges`, and a tmpfs `/tmp`. The task-queue directory is the only read-write mount.

**Config pattern (`~/.claude.json`, global):**
```json
{
  "task-queue": {
    "type": "http",
    "url": "http://127.0.0.1:8485/mcp"
  }
}
```

**Security:** No authentication — LAN-only, not proxied externally. Same accepted-risk pattern as homelab-ops. Container hardening (cap_drop, read-only filesystem, UID 1000) prevents privilege escalation.

**Standalone value:** High for multi-agent setups using a file-based task queue. Pairs with the task-dispatcher PM2 cron and the Matrix/ntfy approval gates. For single-agent setups, you can write task files directly without the indirection.

See [task-queue-mcp.md](../docs/components/task-queue-mcp.md) for the schema, transition rules, and dispatcher integration.

---

## Choosing Your MCP Stack

You don't need all of these. Here's a prioritized adoption path:

**Start here (essential):**
1. Desktop Commander (Claude Desktop) or homelab-ops (Claude Code / LibreChat) — filesystem and shell access
2. basic-memory — persistent notes between sessions

**Add web search:**
3. SearXNG MCP — private web search with no API costs (if you self-host SearXNG)

**Add monitoring (if you run monitoring):**
4. Netdata — real-time metrics from your hosts
5. Grafana — dashboards, historical data, alerts

**Add infrastructure access (based on what you run):**
6. Unraid MCP or TrueNAS MCP — direct server management
7. InfluxDB — time-series queries

**Add search and knowledge (Layer 3):**
8. qmd — semantic search over your docs and memory
9. memsearch — memory recall from past Claude Code sessions
10. GitHub — repo management from within Claude

**Add for multi-agent setups:**
11. scoped-mcp — per-agent tool proxy with manifest-based scoping, credential isolation, and audit logging (essential once you have two or more agents sharing infrastructure)
12. task-queue-mcp — schema-validated access to the agent task queue (pairs with a dispatcher and approval gates)
13. matrix-mcp — persistent, threaded agent communications via a self-hosted Synapse homeserver
14. graphiti-mcp — temporal knowledge graph for relational queries about infrastructure topology

**Add as needed:**
15. Playwright — browser automation
16. pm2-mcp — PM2 process inspection and management (if you use PM2)
17. ntfy-mcp — push notifications from agents (if you run ntfy)
18. Backrest — backup management (if you use Backrest/restic)
19. helm-ops-mcp — remote-host shell and file ops over SSH (only if you build on a second machine)
20. Fluxer — chat bot for Fluxer platform (shelved, community use case)
21. jobsearch-mcp — job search and application tracking
22. Bluesky — social media (niche use case)

## Notes on MCP Transport

Most MCP servers use **stdio** transport — Claude Desktop launches them as a
subprocess and communicates via stdin/stdout. This is the simplest approach and
works well for servers that only need one client at a time.

Several servers in this stack use **HTTP** (streamable-HTTP) transport instead,
which is useful when:
- Multiple clients need to connect (e.g., Claude Code + LibreChat)
- The server needs to run as a long-lived service (managed by PM2)
- You want to expose the server on the network

homelab-ops, helm-ops-mcp, pm2-mcp, matrix-mcp, SearXNG MCP, and qmd (in HTTP mode)
all run as PM2 services with HTTP transport. ntfy-mcp, task-queue-mcp, and
graphiti-mcp run as Docker containers with HTTP transport. LibreChat containers
reach them via `host.docker.internal`; Claude Code connects directly to
`localhost`. scoped-mcp is the exception in this stack — it uses stdio transport
because each agent process launches its own scoped instance.

See the `pm2/` directory for ecosystem config examples.

---

## Related Docs

- [Architecture overview](../README.md#layer-1--host--core-tooling) — Layer 1 context for MCP servers
- [PM2 ecosystem config](../pm2/ecosystem.config.js.example) — service definitions for always-on MCP servers (qmd HTTP mode)
- [LibreChat MCP integration](../docs/components/librechat.md#mcp-integration) — connecting LibreChat to host-level MCP servers
- [CLAUDE.md examples](../claude-code/) — how agents reference MCP tools in their project context
