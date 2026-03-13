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

### homelab-ops

**Purpose:** Filesystem operations, shell commands, file editing, process
inspection on the host machine.

**Built by:** me — a FastMCP (Python) server purpose-built for homelab operations.

**GitHub:** https://github.com/TadMSTR/homelab-agent (see `mcp-servers/` notes)

**Why it's here:** Claude needs to read and write files, run shell commands, and
manage processes. This is the hands and feet of the operation. I originally used
Desktop Commander for this but replaced it with a custom server that exposes
exactly the tools I need and runs as an HTTP service — making it available to
both Claude Code and LibreChat agents simultaneously.

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

**Config pattern (Claude Code `settings.json`):**
```json
{
  "homelab-ops": {
    "type": "url",
    "url": "http://localhost:8282/mcp"
  }
}
```

**Standalone value:** Essential. This is the minimum viable MCP server for
infrastructure work. The HTTP transport means multiple clients can share it
without fighting over a stdio subprocess.

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
a self-hosted SearXNG instance that aggregates results from multiple engines
with no tracking. Three tools: `search` (query with category/engine filters),
`fetch_url` (retrieve full page content), and `search_and_fetch` (search + fetch
top results in one call).

**Prerequisites:** A running SearXNG instance with JSON format enabled in
`settings.yml`.

**Config pattern (Claude Code `settings.json`):**
```json
{
  "searxng": {
    "type": "url",
    "url": "http://localhost:YOUR_PORT/mcp"
  }
}
```

**Standalone value:** High. If you self-host SearXNG, this gives any Claude Code
session private web search with zero API costs.

---

### Fluxer MCP

**Purpose:** Discord bot gateway + MCP tools for community interaction via the
Fluxer platform.

**Built by:** me — TypeScript, runs as a PM2 service.

**GitHub:** https://github.com/TadMSTR/fluxer-mcp-server

**Why it's here:** Optional. I maintain a Discord bot in a homelab community
that answers questions about this project. The MCP server exposes three tools
(`get_bot_status`, `send_message`, `get_messages`) for manual control from
Claude Desktop, while the gateway listener handles autonomous responses using
Claude Haiku.

**Standalone value:** Low unless you're active in a Discord community and want
Claude to help manage a bot presence.

---

### jobsearch-mcp

**Purpose:** Multi-board job search, resume scoring, and application tracking —
all from a LibreChat agent.

**Built by:** me — FastMCP (Python), designed for multi-user LibreChat deployments.

**GitHub:** https://github.com/TadMSTR/jobsearch-mcp

**Why it's here:** A personal project that turned into a good example of building
a non-trivial FastMCP server with Postgres persistence, vector search (Qdrant),
and per-user state in a multi-user LibreChat environment.

**Standalone value:** Medium. Useful if you're job hunting and want to aggregate
searches across Adzuna, Remotive, WeWorkRemotely, Jobicy, and LinkedIn from a
single interface. Requires Postgres and optionally Qdrant for semantic matching.

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

## Choosing Your MCP Stack

You don't need all of these. Here's a prioritized adoption path:

**Start here (essential):**
1. homelab-ops (or any shell/file MCP server) — filesystem and shell access
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

**Add as needed:**
11. Playwright — browser automation
12. Backrest — backup management (if you use Backrest/restic)
13. Fluxer — Discord bot management (community use case)
14. jobsearch-mcp — job search and application tracking
15. Bluesky — social media (niche use case)

## Notes on MCP Transport

Most MCP servers use **stdio** transport — Claude Desktop launches them as a
subprocess and communicates via stdin/stdout. This is the simplest approach and
works well for servers that only need one client at a time.

Several servers in this stack use **HTTP** (streamable-HTTP) transport instead,
which is useful when:
- Multiple clients need to connect (e.g., Claude Code + LibreChat)
- The server needs to run as a long-lived service (managed by PM2)
- You want to expose the server on the network

homelab-ops, SearXNG MCP, and qmd (in HTTP mode) all run as PM2 services with
HTTP transport. LibreChat containers reach them via `host.docker.internal`;
Claude Code connects directly to `localhost`. See the `pm2/` directory for
ecosystem config examples.

---

## Related Docs

- [Architecture overview](../README.md#layer-1--host--core-tooling) — Layer 1 context for MCP servers
- [PM2 ecosystem config](../pm2/ecosystem.config.js.example) — service definitions for always-on MCP servers (qmd HTTP mode)
- [LibreChat MCP integration](../docs/components/librechat.md#mcp-integration) — connecting LibreChat to host-level MCP servers
- [CLAUDE.md examples](../claude-code/) — how agents reference MCP tools in their project context
