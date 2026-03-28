# Helm Dashboard

The Helm Dashboard is a CloudCLI plugin that adds a dedicated monitoring tab to the browser UI. It's the observation layer for walk-away agent builds — eight panels covering agent sessions, memory state, handoff queue, knowledge graph, infrastructure status, build progress, project tracking, and real-time WebSocket updates. While the build agent runs in the background with auto mode handling routine approvals, the dashboard gives you a live view without requiring a terminal session.

- **Repo:** `cloudcli-plugin-helm-dashboard` (personal)
- **Plugin host:** CloudCLI (`@siteboon/claude-code-ui`) via the plugin API
- **Runtime:** TypeScript backend + esbuild-bundled frontend
- **Process:** Started automatically by CloudCLI on load

## Why It's Here

When you run Claude Code unattended with auto mode enabled, you need visibility without presence. The agent handles routine approvals itself; you check the dashboard when something interesting happens, and ntfy notifies you when a decision needs a human. The alternative — watching terminal output or tailing log files — breaks the walk-away model.

CloudCLI's plugin system makes this clean. The plugin runs its own HTTP and WebSocket backend, CloudCLI proxies requests to it, and the result is a tab in the same browser session where you manage your Claude Code projects.

## Architecture

The plugin has a TypeScript backend and a bundled frontend:

```
cloudcli-plugin-helm-dashboard/
├── src/
│   ├── server.ts           # HTTP server — /health, /agents, panel data endpoints
│   ├── clients/
│   │   ├── graphiti.ts     # Graphiti MCP Streamable HTTP client
│   │   └── ntfy.ts         # Push notification client
│   └── panels/
│       ├── agents.ts       # Agent session scanner
│       ├── memory.ts       # Memory file browser
│       ├── handoff.ts      # Handoff queue reader
│       ├── graph.ts        # Knowledge graph query panel
│       ├── infra.ts        # PM2 jlist + Docker ps
│       ├── build.ts        # Build plan progress tracking
│       └── plane.ts        # Plane work items via REST API
├── index.ts                # Frontend shell + panel registry
├── deploy.sh               # Build → install → restart cycle
└── package.json
```

**Frontend bundling:** CloudCLI loads plugin frontends via dynamic import. Relative ES module imports don't resolve correctly from the plugin host context — the frontend must be a single bundled ESM file. The project uses esbuild; other bundlers should also work.

**WebSocket server:** The plugin starts its own WebSocket server using the `ws` library for file watcher–driven live updates. Node 22 has no built-in WebSocket server API.

**Graphiti client:** Uses the Streamable HTTP transport (MCP 2025-03-26 spec) — SSE responses with session IDs, not simple JSON-RPC. The client handles session expiry and auto-reconnects.

**Plane integration:** Calls the Plane REST API directly (`/api/v1/workspaces/{slug}/work-items/`) rather than through the stdio-based Plane MCP server, which can't be called from a web backend process.

## Prerequisites

- CloudCLI installed and running via PM2 — see [cloudcli.md](cloudcli.md)
- Node.js 22+ with npm on the host
- Graphiti running and accessible at localhost — see [graphiti.md](graphiti.md)
- Plane with API access — see [plane.md](plane.md)
- ntfy instance for push notifications
- SWAG reverse proxy with `/plugin-ws/` location block (see below)
- Auto mode configuration is optional but the intended use case — see [auto-mode.md](auto-mode.md)

## Installation

```bash
# Clone the plugin repo
git clone <your-plugin-repo> ~/repos/personal/cloudcli-plugin-helm-dashboard
cd ~/repos/personal/cloudcli-plugin-helm-dashboard

# Install dependencies — devDeps are required for the build step
npm install --include=dev

# Build and install
bash deploy.sh
```

`deploy.sh` builds the TypeScript, copies the plugin to `~/.claude-code-ui/plugins/cloudcli-plugin-helm-dashboard/`, updates `~/.claude-code-ui/plugins.json`, and restarts CloudCLI via PM2. It must copy — symlinks don't work because CloudCLI's plugin discovery uses `readdirSync({withFileTypes:true})`, which reports symlinks as non-directories and skips them.

After installation, the Helm Dashboard tab appears in CloudCLI on next load.

## SWAG Proxy Configuration

The plugin uses WebSockets for live updates. CloudCLI proxies plugin WebSocket traffic at `/plugin-ws/<plugin-name>`, which needs a dedicated SWAG location block — exempt from Authelia, with explicit WebSocket upgrade headers.

Add this to your CloudCLI SWAG conf alongside the existing `/ws` block:

```nginx
# Plugin WebSocket — exempt from Authelia, WebSocket upgrade required
location /plugin-ws/ {
    include /config/nginx/resolver.conf;
    set $upstream_app  YOUR_HOST_IP;
    set $upstream_port 3004;
    set $upstream_proto http;
    proxy_pass $upstream_proto://$upstream_app:$upstream_port;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;
}
```

The `/plugin-ws/` path bypasses Authelia for the same reason the `/ws` path does — WebSocket upgrades can't go through the `auth_request` subrequest flow. CloudCLI's own JWT authentication covers this endpoint.

## Configuration

The plugin reads configuration from `config.json` in the plugin directory:

```json
{
  "graphiti": {
    "url": "http://localhost:8000"
  },
  "plane": {
    "url": "http://localhost:8180",
    "api_key": "YOUR_PLANE_API_KEY",
    "workspace_slug": "YOUR_WORKSPACE_SLUG"
  },
  "ntfy": {
    "url": "https://ntfy.yourdomain/helm-dashboard",
    "token": "YOUR_NTFY_TOKEN"
  }
}
```

Use the Plane internal port (`8180` in this setup) rather than the SWAG proxy URL — the plugin backend runs on the same host and doesn't need to go through the proxy.

## Panel Reference

| Panel | Data Source | What It Shows |
|-------|-------------|---------------|
| Agent Status | `~/.claude/projects/` filesystem scan | Active sessions, project count, last-active timestamps |
| Memory Browser | `~/.claude/memory/` filesystem | Working memory files, recent writes, tier breakdown |
| Handoff Queue | `~/.claude/projects/*/` queue dirs | Pending tasks, in-progress items, recent completions |
| Knowledge Graph | Graphiti MCP (Streamable HTTP) | `search_nodes` / `search_facts` on infrastructure topology |
| Infrastructure | PM2 jlist + `docker ps` | PM2 process status, Docker container state |
| Build Progress | Build plan files + memory | Current phase, completed steps, blockers |
| Plane | Plane REST API | Active work items, modules, current sprint/cycle |
| Live Updates | WebSocket + file watchers | Real-time notifications for queue changes and agent events |

## Integration Points

The dashboard is read-only with respect to the agent system — it observes, it doesn't control. It reads:

- `~/.claude/projects/` — agent session and queue state
- `~/.claude/memory/` — working memory files
- Graphiti MCP at `localhost:8000` (Streamable HTTP)
- Plane REST API at `localhost:8180`
- PM2 via `pm2 jlist` subprocess
- Docker via `docker ps` subprocess

ntfy notifications are write-only — the plugin sends alerts but doesn't read notification history.

The dashboard pairs naturally with auto mode (see [auto-mode.md](auto-mode.md)) — auto mode handles unattended approval, the dashboard provides visibility into what got approved and what's waiting.

## Gotchas

**Symlinks don't work for plugin installation.** CloudCLI's plugin discovery skips symlinked directories. The deploy script always does a full copy — don't try to shortcut this.

**Re-run `deploy.sh` after every CloudCLI update.** `npm install -g @siteboon/claude-code-ui@latest` reinstalls from scratch and wipes `~/.claude-code-ui/`. The plugin install needs to be re-applied. The script is idempotent — safe to run any time.

**Plane REST path is `work-items/`, not `issues/`.** Older Plane documentation and some integrations use `/issues/`, which 404s on current versions. The correct path is `/api/v1/workspaces/{slug}/work-items/`.

**esbuild is required for the build.** The frontend must bundle to a single ESM file — relative imports don't resolve from the CloudCLI plugin host context. The `package.json` build script calls esbuild directly.

**`/plugin-ws/` is Authelia-exempt.** This is a deliberate trade-off, flagged in the security audit. WebSocket upgrades can't go through Authelia's `auth_request` subrequest flow. CloudCLI's JWT covers the endpoint; the security audit has the full analysis.

## Standalone Value

The Helm Dashboard plugin is fairly specific to this stack — it reads from the memory layout, Graphiti instance, and Plane deployment described in other component docs. It's not a drop-in for a generic Claude Code setup.

The plugin architecture itself is reusable. The pattern — TypeScript backend, esbuild-bundled frontend, deployed to `~/.claude-code-ui/plugins/`, proxied via CloudCLI — works for any custom monitoring tab you want to add to CloudCLI. The Graphiti Streamable HTTP client and the PM2/Docker subprocess wrappers are independently useful starting points.
