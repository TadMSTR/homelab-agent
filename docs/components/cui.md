# CUI

CUI (Claude Code UI) is a lightweight browser-based interface for Claude Code. Its primary value in this stack is visibility into headless agent runs — you can watch a PM2-managed Claude Code job execute in real time, get push notifications when long-running tasks complete, and intervene if something goes sideways. It's not meant to replace the terminal; it's meant to give you a window into activity that would otherwise be invisible.

CUI complements [CloudCLI](cloudcli.md) rather than competing with it. CloudCLI is the richer interactive interface — file explorer, git integration, shell terminal, MCP server management. CUI is narrower but starts instantly and works well on a phone or secondary device where you just want to check in on a running job.

- **Source:** [wbopan/cui](https://github.com/wbopan/cui)
- **Transport:** HTTP
- **Process manager:** PM2
- **Default port:** 3001

## Why CUI

When you're running Claude Code agents via PM2 — memory sync at 4 AM, doc health checks on Sunday night, background research jobs — you lose the real-time feedback of watching a terminal. CUI restores that visibility from a browser, including push notifications so you don't have to poll for completion.

The push notification setup is what makes it genuinely useful. A 20-minute memory sync run you've kicked off and walked away from will notify you on your phone when it finishes (or fails). Without that, you're checking PM2 logs manually and guessing whether it's still running.

## Installation

CUI requires Node.js and Claude Code to be installed on the host.

```bash
npm install -g @wbopan/cui
```

Verify it installed:

```bash
cui-server --version
```

## PM2 Configuration

CUI runs as an always-on PM2 service. Add it to your ecosystem config:

```js
{
  name: 'cui',
  script: 'cui-server',  // Resolves via npm global bin path
  autorestart: true,
  max_restarts: 10,
  env: {
    PORT: 3001,
  },
}
```

If `cui-server` doesn't resolve, use the full path:

```bash
which cui-server   # Find the installed binary
```

Then register and save:

```bash
pm2 start ecosystem.config.js --only cui
pm2 save
```

## SWAG Proxy Configuration

CUI uses WebSockets for the terminal stream. Like CloudCLI, the WebSocket path needs a separate nginx location block — the standard `proxy.conf` include strips the `Connection: Upgrade` header and breaks the WebSocket handshake.

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name cui.yourdomain.*;

    include /config/nginx/ssl.conf;
    include /config/nginx/authelia-server.conf;

    location / {
        include /config/nginx/authelia-location.conf;
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app  YOUR_HOST_IP;
        set $upstream_port 3001;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;
    }

    # WebSocket — separate block, no auth_request
    location /socket.io/ {
        include /config/nginx/resolver.conf;
        set $upstream_app  YOUR_HOST_IP;
        set $upstream_port 3001;
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

The `/socket.io/` path is exempt from `auth_request` for the same reason as CloudCLI's `/ws` — WebSocket upgrades can't go through the Authelia subrequest flow. CUI handles its own session management for that endpoint.

## Push Notifications

CUI can send push notifications when agent sessions complete or hit errors. Configure a notification webhook or ntfy topic in CUI's settings. If you're already running an ntfy server in your stack (the resource-monitor and backup scripts use it), point CUI at the same instance:

```
ntfy topic: YOUR_TOPIC_NAME
ntfy server: http://YOUR_NTFY_HOST:PORT
```

With this configured, any Claude Code session that finishes — whether you kicked it off manually in the CUI terminal or it's a PM2 background job — sends a notification. The notification includes the session exit status, so you know whether to investigate.

## Relationship to CloudCLI

Both tools give you browser-based Claude Code access, but they're optimized for different use cases:

| | CUI | CloudCLI |
|---|---|---|
| Primary use | Monitor running/headless jobs | Start and manage interactive sessions |
| File explorer | No | Yes |
| Git integration | No | Yes |
| Shell terminal | Yes (basic) | Yes (full) |
| MCP server management | No | Yes |
| Push notifications | Yes | No |
| Setup complexity | Simple | Moderate (env var required) |

If you're running PM2 background agents and want visibility into them, start with CUI. If you want a full interactive Claude Code environment in the browser, use CloudCLI. They share the same `~/.claude/` state — sessions and MCP config are consistent across both.

## Standalone Value

Medium-high. Most useful once you have PM2 cron jobs running that you want to monitor. If you're using Claude Code purely interactively in the terminal, CUI doesn't add much. But as soon as you have background agents running on schedules, the ability to watch them execute (and get notified when they finish) is worth the 10-minute setup.

## Related Docs

- [CloudCLI](cloudcli.md) — richer interactive Claude Code browser UI
- [Agent Panel](agent-panel.md) — broader operations panel (PM2, Docker, files, diagnostics)
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — service definitions
