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
review PRs without you switching to a browser. Especially useful for the
memory-sync agent that commits to your context repo.

**Tip:** If you have multiple GitHub accounts (personal + work), configure
separate MCP server entries with different SSH keys or tokens. Label them
clearly (`github-personal`, `github-work`) so Claude knows which to use.

---

### Desktop Commander

**Purpose:** Filesystem operations, terminal commands, process management on the
host machine.

**Package:** `@anthropic/desktop-commander` (npm)

**Why it's here:** Claude needs to read and write files, run shell commands, and
manage processes. This is the hands and feet of the operation.

**Config pattern:**
```json
{
  "desktop-commander": {
    "command": "npx",
    "args": ["-y", "@anthropic/desktop-commander"]
  }
}
```

**Standalone value:** Essential. This is the minimum viable MCP server — without
it, Claude can't interact with the filesystem at all.

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

## Choosing Your MCP Stack

You don't need all of these. Here's a prioritized adoption path:

**Start here (essential):**
1. Desktop Commander — filesystem and shell access
2. basic-memory — persistent notes between sessions

**Add monitoring (if you run monitoring):**
3. Netdata — real-time metrics from your hosts
4. Grafana — dashboards, historical data, alerts

**Add infrastructure access (based on what you run):**
5. Unraid MCP or TrueNAS MCP — direct server management
6. InfluxDB — time-series queries

**Add search and knowledge (Layer 3):**
7. qmd — semantic search over your docs and memory
8. GitHub — repo management from within Claude

**Add as needed:**
9. Playwright — browser automation
10. Bluesky — social media (niche use case)

## Notes on MCP Transport

Most MCP servers use **stdio** transport — Claude Desktop launches them as a
subprocess and communicates via stdin/stdout. This is the simplest and most
reliable approach.

Some servers also support **HTTP** transport, which is useful when:
- Multiple clients need to connect (e.g., LibreChat + Claude Desktop)
- The server needs to run as a long-lived service (managed by PM2)
- You want to expose the server on the network

For HTTP transport, run the server as a PM2 service and point clients at
`http://localhost:PORT`. See the `pm2/` directory for examples.
