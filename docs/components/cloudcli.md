# CloudCLI

CloudCLI (also known as claudecodeui) is a self-hosted web UI for Claude Code. It gives you a browser-based interface for starting and managing Claude Code sessions, with a file explorer, git integration, shell terminal, and MCP server management built in. It reads from and writes to the same `~/.claude` config that Claude Code uses natively.

It complements [CUI](https://github.com/wbopan/cui) rather than replacing it. CUI's primary value in this setup is visibility into headless agent runs and push notifications. CloudCLI is a richer interactive interface — more useful for starting new project sessions or exploring a codebase.

- **Source:** [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) (GPL v3)
- **Transport:** HTTP
- **Process manager:** PM2

## Why CloudCLI

The Claude Code CLI is powerful but text-only — no file tree, no git diff viewer, no way to manage MCP servers from a UI. CloudCLI fills that gap while staying fully local. Because it talks directly to Claude Code (not the API), it uses your existing `claude.json` config, respects your MCP servers, and doesn't require an additional API key or pricing tier.

It also supports Cursor CLI, Codex, and Gemini CLI, which makes it worth running even if you add other coding assistants to the stack later.

## Installation

CloudCLI runs as a Node.js application via PM2. Claude Code must already be installed on the host.

```bash
# Install Claude Code if not already present
npm install -g @anthropic-ai/claude-code

# Clone CloudCLI
git clone https://github.com/siteboon/claudecodeui.git ~/apps/cloudcli
cd ~/apps/cloudcli
npm install

# Build the frontend
npm run build
```

### Environment

Create a `.env` file in the CloudCLI directory:

```bash
PORT=3004
VITE_IS_PLATFORM=true
```

`VITE_IS_PLATFORM=true` is required. Without it, the app's routing and auth flow don't work correctly when accessed through a reverse proxy.

> **Note:** If you're adding CloudCLI to an existing PM2 ecosystem, set `VITE_IS_PLATFORM=true` in the environment block. If PM2 was started without this variable, you need to delete and re-register the process — `pm2 restart` won't pick up new env vars from `.env`.

### PM2 Registration

```bash
pm2 start npm --name cloudcli -- start
pm2 save
```

Or in an ecosystem file:

```js
{
  name: 'cloudcli',
  cwd: '/home/YOUR_USER/apps/cloudcli',
  script: 'npm',
  args: 'start',
  env: {
    PORT: 3004,
    VITE_IS_PLATFORM: 'true',
  },
}
```

## SWAG Proxy Configuration

CloudCLI uses WebSockets for the chat interface. The proxy configuration requires a dedicated location block for the WebSocket path — **do not use the standard `proxy.conf` include for `/ws`**, as it clears the `Connection` header and breaks the WebSocket upgrade.

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name cloudcli.yourdomain.*;

    include /config/nginx/ssl.conf;
    include /config/nginx/authelia-server.conf;

    location / {
        include /config/nginx/authelia-location.conf;
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app  YOUR_HOST_IP;
        set $upstream_port 3004;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;
    }

    # WebSocket path — separate block, exempt from Authelia
    location /ws {
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
}
```

**Why `/ws` must be a separate block:** The standard `proxy.conf` include sets `Connection ""`, which strips the `Connection: Upgrade` header — the WebSocket handshake fails silently and chat sessions never complete. A dedicated block with explicit `proxy_http_version 1.1` and `Connection "upgrade"` lets the upgrade survive the proxy hop.

**Why `/ws` is exempt from Authelia:** `auth_request` triggers a subrequest to Authelia before proxying. WebSocket upgrades can't go through the subrequest flow. The `/ws` path skips `auth_request`; CloudCLI's own JWT handles authentication for that endpoint.

## Troubleshooting

### "Network error" on login

Almost always a stale JWT in the browser's localStorage from a previous session or reinstall. Fix:

1. Open DevTools → Application → Local Storage
2. Delete the entry for your CloudCLI domain
3. Reload and log in again

### Chat never completes / WebSocket errors

Check the nginx error log in the SWAG container:

```bash
docker exec swag tail -n 50 /var/log/nginx/error.log
```

If the WebSocket upgrade is failing, verify the `/ws` location block is present and not using `proxy.conf`. See the proxy configuration above.

### VITE_IS_PLATFORM not taking effect

PM2 doesn't reload `.env` on restart — you need to delete and re-register the process:

```bash
pm2 delete cloudcli
pm2 start npm --name cloudcli -- start
pm2 save
```

## Integration Points

CloudCLI reads `~/.claude/` directly — CLAUDE.md files, MCP server configuration, and project sessions are all visible immediately without additional setup. MCP servers added via the CloudCLI UI are written back to `~/.claude.json`, making them available to Claude Code in the terminal as well.

If you're running CloudCLI alongside CUI, they share the same session state via `~/.claude/`. Changes in one (MCP config, CLAUDE.md edits) are visible in the other.
