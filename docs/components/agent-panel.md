# Agent Panel

The agent panel is a purpose-built web UI for the homelab agent host. It surfaces everything you need to monitor and operate the system from a browser: service health, PM2 process management, Docker containers, system resources, process logs, file browsing and editing, Backrest backup history, and a diagnostics runner.

It's a single Node.js/Express process — no build step, no framework, no database. One HTML file, one JS file, one server.

- **Source:** [`TadMSTR/claudebox-panel`](https://github.com/TadMSTR/claudebox-panel)
- **Transport:** HTTP (behind SWAG reverse proxy)
- **Process manager:** PM2
- **Port:** 3003 (default)

## Why a Custom Panel

Generic dashboards (Portainer, Dashdot, Netdata) each cover part of the picture. None of them know about PM2, the file tree you actually want to browse, your Backrest backup jobs, or your custom diagnostics. A small custom panel that knows the exact shape of this stack is more useful than stitching together five generic ones.

It also serves as a useful example of what Claude Code can build and maintain. Most of this panel's code was written and extended by agents — the AI can browse, edit, and improve the same code it runs on.

## Security Model

The panel uses a three-layer auth stack:

```
Browser → Authelia (SSO) → SWAG (injects token) → Panel (validates token)
```

1. **Authelia** — SSO gate. Every request to the subdomain goes through `auth_request`. Unauthenticated requests redirect to the login page.
2. **SWAG** — After Authelia passes the request, SWAG injects `X-Panel-Token` via `proxy_set_header`. The browser never sees or handles the token — it's added server-side.
3. **Panel** — Every `/api/*` route validates `X-Panel-Token` with a constant-time comparison (`crypto.timingSafeEqual`). Requests without the correct token get a 401.

This means even if Authelia were bypassed, an attacker without the token still can't call any API route. The token lives only in the SWAG proxy conf — not in the browser, not in the client-side JS, not in any log.

**Network restriction:** Port 3003 should be restricted at the firewall to localhost and the Docker bridge subnet. On a Linux host with `iptables`:

```bash
sudo iptables -A INPUT -p tcp --dport 3003 -s 127.0.0.1 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 3003 -s 172.18.0.0/16 -j ACCEPT  # Docker bridge — adjust subnet to match yours
sudo iptables -A INPUT -p tcp --dport 3003 -j DROP
sudo netfilter-persistent save  # persist across reboots (requires iptables-persistent)
```

## Installation

```bash
git clone https://github.com/TadMSTR/claudebox-panel.git ~/apps/claudebox-panel
cd ~/apps/claudebox-panel
npm install
```

### Environment

Create a `.env` file in the app directory:

```bash
PANEL_TOKEN=your-token-here  # generate with: openssl rand -hex 32
```

### Configuration

Edit `config/config.js` to set:

- `port` — which port to listen on (default: 3003)
- `allowedOrigins` — CORS allowed origins (set to your panel subdomain)
- `agentsDir` — root directory for the Agents panel (defaults to `~/.claude/projects/`)
- `filePaths` — directories and files exposed in the file browser
- `editableExtensions` — which file types can be edited (`.env` is intentionally excluded)
- `services` — health check endpoints shown in the Services panel
- `diagnostics` — expected Docker containers, PM2 processes, NFS mounts, ports, etc.

### PM2 Registration

```bash
pm2 start npm --name agent-panel -- start
pm2 save
```

Or in an ecosystem file:

```js
{
  name: 'agent-panel',
  cwd: '/home/YOUR_USER/apps/claudebox-panel',
  script: 'npm',
  args: 'start',
}
```

## SWAG Proxy Configuration

The panel subdomain conf must inject the `X-Panel-Token` header — this is what authenticates requests to the panel API.

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name panel.yourdomain.*;

    include /config/nginx/ssl.conf;
    include /config/nginx/authelia-server.conf;

    location / {
        include /config/nginx/authelia-location.conf;
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app  YOUR_HOST_IP;
        set $upstream_port 3003;
        set $upstream_proto http;
        proxy_set_header X-Panel-Token "YOUR_TOKEN_HERE";
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;
    }
}
```

The token in `proxy_set_header` must match `PANEL_TOKEN` in `.env`.

## Features

**Services** — health check grid for all configured services. Shows up/down status, latency, and a dot-history strip for the last N checks. Auto-refreshes every 30 seconds.

**Resources** — CPU load averages (1m/5m/15m), memory usage, disk usage per mount. Progress bars with warn/danger thresholds.

**PM2 Processes** — table of all PM2 processes split into always-on and scheduled sections. Shows status, PID, restarts, CPU, memory, uptime. Restart/stop/start actions per process.

**Docker** — container list with state and status. Read-only — the panel can observe containers but not manage them (no restart/stop actions by design).

**Logs** — PM2 process log viewer. Select process, stream (stdout/stderr), line count. Filter by keyword with live highlight.

**Backrest** — recent backup operation history from a local Backrest instance. Shows plan, repo, status, start time, and duration.

**Diagnostics** — structured health check runner with lightweight and thorough modes. Checks: Docker container state, PM2 process health, NFS mount availability, port listening, TLS cert expiry, DNS resolution, cross-host ping, disk usage, git repo state. Failures alert via ntfy.

**Agents** — dual-pane interface for browsing Claude Code agent sessions and project files. Left pane: project list sorted by last activity with session counts; selecting a project shows its sessions with timestamp, message count, and first-user-message preview; selecting a session shows the conversation — user and assistant turns with tool call names listed. Right pane: read-only file browser scoped to the agent projects directory (`agentsDir` in config), useful for inspecting CLAUDE.md files, memory, and build plan artifacts without opening a terminal. Symlinked files (e.g., CLAUDE.md → prime-directive source) are handled correctly.

**File Browser** — read/write access to a configured whitelist of directories and files. Supports view, edit, save-with-backup, revert, and backup discard. Diff shown before save. `.panelbak` files created on first write; stale backups (>7 days) cleaned up on startup.

**Dependency Updates** — tracks update availability for key agent stack dependencies. A background script populates a JSON sidecar; the panel reads it and shows a badge with the pending update count. Each dependency row shows whether a safe update can be applied in-panel, delegated to an AI agent via CloudCLI, or is pinned/manually managed. Applies safe updates as background tasks with live polling. Maintains an audit log of every update applied.

## Dependency Updates Configuration

The dep-updates feature has two parts: a check script that runs on a schedule and the panel backend that reads and acts on its output.

### Check Script

A shell script (`check-dep-updates.sh`) runs via PM2 cron job `dep-update-check` (Wednesdays at noon by default) and writes a JSON sidecar to a known path. The panel reads the sidecar on demand — no polling, no persistent connection.

The script checks each dependency using whatever mechanism makes sense for that package manager:

- npm packages at system prefixes — `npm outdated -g --json`
- pip packages — `pip show`
- Self-managed tools — compare installed version against GitHub releases or a published API
- System packages — compare against the upstream latest via an API call

Each entry in the sidecar follows the same shape:

```json
{
  "name": "dep-name",
  "current": "1.2.3",
  "latest": "1.4.0",
  "breaking": false,
  "pinned": false,
  "canSafeUpdate": true,
  "updateCommand": "npm install -g dep-name@latest"
}
```

`canSafeUpdate` is true when the dep is on the safe-update allowlist and `breaking` is false. The allowlist in `config/config.js` is the mechanism for overriding what counts as "safe" — if a major-version bump is known-safe for your stack, add the update command to the allowlist.

### Panel Configuration

```js
depUpdates: {
  sidecarPath: '/home/YOUR_USER/.local/share/logs/dep-updates-latest.json',
  safeUpdateCommands: [
    'npm install -g qmd@latest',
    // add commands for deps you're comfortable auto-updating
  ],
  pinned: {
    'nodejs': 'system-managed — update via OS package manager',
    'authelia': 'pinned at 4.x — review breaking changes before upgrading',
  }
}
```

`pinned` entries appear in the panel UI with the reason string shown to the user. They never show a safe-update button. This keeps frozen packages out of the badge count and surfaces the freeze reason so you don't forget why you pinned it.

### Delegation to CloudCLI

Dependencies that can't be updated with a single shell command — those with post-update patches, config migrations, or multi-step procedures — can be delegated to a Claude Code agent via CloudCLI. The panel opens a pre-filled prompt in CloudCLI's chat interface. You review and run it there. This keeps complex updates out of the panel's background task system while still surfacing them in the same UI.

### Audit Log

Every update applied through the panel (safe update or delegation) is appended to an audit JSONL file:

```json
{"ts": "2026-03-15T14:22:00Z", "dep": "qmd", "from": "1.2.3", "to": "1.4.0", "method": "safe-update"}
```

The panel's audit view shows the log in reverse chronological order. Include the audit log in your backup and deploy-restore coverage — it's the only record of what was updated and when.

## Diagnostics Configuration

The diagnostics system is driven entirely by `config/config.js`. Key fields:

```js
diagnostics: {
  expectedContainers: ['swag', 'authelia', ...],  // must be running
  expectedPM2: ['qmd', 'agent-panel', ...], // must be online
  nfsMounts: ['/mnt/storage/backup'],              // must be mounted
  expectedPorts: [{ port: 443, label: 'swag' }, ...],
  tlsCertPath: '/path/to/fullchain.pem',
  deepChecks: [{ label: 'App', url: 'https://...', expectStatus: 200 }],
  gitRepos: [{ label: 'my-repo', path: '/home/user/repos/my-repo' }],
  pingHosts: [{ label: 'storage', host: '10.0.0.9' }],
  dnsChecks: ['yourdomain.com'],
  ntfyUrl: 'https://ntfy.youserver/topic',  // optional
}
```

Lightweight mode skips thorough-only checks (deep endpoint probes, Docker restart counts, NFS responsiveness, DNS, cross-host ping, git state, log size). Use lightweight for scheduled health checks; run thorough mode manually or on-demand.

## Troubleshooting

### 401 on all API calls

Token mismatch. Verify `PANEL_TOKEN` in `.env` matches `proxy_set_header X-Panel-Token` in the SWAG conf. Restart the panel after any `.env` change.

### File browser shows no roots

Check `filePaths` in `config/config.js`. Paths that don't exist or aren't accessible will be silently skipped.

### Diagnostics show stale results

Results are cached in memory — they reset when the PM2 process restarts. Use "cached results" to fetch the last run, or trigger a new run manually.
