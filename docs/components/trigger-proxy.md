# Trigger Proxy

`trigger-proxy` is a lightweight Python HTTP server that lets n8n Docker workflows fire Claude Code RemoteTrigger sessions. Because n8n runs inside Docker, it cannot reach the claude.ai API using the host's OAuth credentials — the proxy handles credential management and forwards the trigger call on n8n's behalf.

**Script:** `~/scripts/trigger-proxy.py`  
**PM2 service:** `trigger-proxy` (always-on)  
**Bind address:** `172.18.0.1:5679` (Docker bridge host address)

## Why It Exists

The autonomous pipeline fires agent sessions in response to task queue events. n8n orchestrates these events as a workflow engine, but n8n runs in Docker and has no direct path to the claude.ai RemoteTrigger API using host credentials. `trigger-proxy` bridges this gap:

1. n8n POSTs a JSON request to `http://172.18.0.1:5679/` (reachable from any container on the Docker bridge network)
2. trigger-proxy validates the secret header, reads the OAuth token from `~/.claude/.credentials.json`, refreshes it if expired, and forwards the call to `api.anthropic.com/v1/code/triggers/{trigger_id}/run`
3. The RemoteTrigger fires an agent session on claude.ai with the task context injected as the prompt payload

## Request Format

```
POST http://172.18.0.1:5679/
Content-Type: application/json
X-Trigger-Secret: <64-char hex>

{
  "trigger_id": "trig_xxxxxxxxxxxxxxxx",
  "target_agent": "writer",
  "task_id": "abc12345-0000-0000-0000-000000000000"
}
```

- `trigger_id` — RemoteTrigger ID from `~/.claude/agent-manifests/.trigger-map.yml`
- `target_agent` — agent name (informational label; the trigger ID determines the actual target project)
- `task_id` — task UUID from the task queue, injected into the RemoteTrigger prompt payload so the agent can pick it up

**Responses:**
- `200 OK` — `{"status": "ok"}` on successful trigger
- `400 Bad Request` — missing or malformed JSON body
- `403 Forbidden` — missing or incorrect `X-Trigger-Secret` header
- `413 Request Entity Too Large` — body exceeds 65,536 bytes

## trigger-map.yml

RemoteTrigger IDs for each agent variant are stored at `~/.claude/agent-manifests/.trigger-map.yml` (file permissions: `0600`):

```yaml
agents:
  dev: trig_xxxxxxxxxxxxxxxx
  writer: trig_xxxxxxxxxxxxxxxx
  research: trig_xxxxxxxxxxxxxxxx
  homelab-ops: trig_xxxxxxxxxxxxxxxx
  security: trig_xxxxxxxxxxxxxxxx
  helm-build: trig_xxxxxxxxxxxxxxxx
  claudebox: trig_xxxxxxxxxxxxxxxx
  librarian: trig_xxxxxxxxxxxxxxxx
```

trigger-proxy loads this file at startup. RemoteTrigger IDs are created in claude.ai project settings — one per agent project. The `trigger_id` field in the request body must match an entry in this map; an unknown ID is passed through to the API, which will return an error.

## OAuth Token Management

The proxy reads `~/.claude/.credentials.json` for the access token. If the token is expired (checked against the `expires_at` timestamp in the credentials file), the proxy refreshes it using the stored refresh token and writes the updated credentials back at `0600` permissions before making the upstream API call.

Credentials are never logged. If the refresh fails, the proxy returns `502 Bad Gateway` and logs the error (without the token value).

## Security Model

Two controls gate access to the proxy:

**1. Bridge network binding** — The proxy binds to `172.18.0.1` (the Docker bridge gateway address), not `0.0.0.0`. Only containers on the Docker bridge network and processes on the host can reach port 5679. Hosts outside the machine, and containers on other Docker networks, cannot.

**2. X-Trigger-Secret header** — Every request must include the correct 64-character hex secret in `X-Trigger-Secret`. Validation uses `secrets.compare_digest` (constant-time comparison, not vulnerable to timing attacks). The secret is provisioned as `TRIGGER_PROXY_SECRET` in the PM2 environment. Requests without the header or with an incorrect value return `403` immediately — no upstream call is made.

**Request size cap** — Bodies larger than 65,536 bytes are rejected before any processing.

**No TLS** — The proxy uses plain HTTP. TLS is not needed because the Docker bridge network is closed to external traffic; n8n and trigger-proxy communicate on a trusted LAN-local segment.

## PM2 Configuration

The service is defined in the claudebox PM2 ecosystem config alongside other always-on services. Key settings:

| Setting | Value |
|---------|-------|
| `script` | `~/scripts/trigger-proxy.py` |
| `interpreter` | `python3` |
| `autorestart` | `true` |
| `TRIGGER_PROXY_SECRET` | 64-char hex (set in PM2 env) |

Logs: `~/.pm2/logs/trigger-proxy-out.log`, `trigger-proxy-error.log`.

```bash
pm2 logs trigger-proxy          # tail recent activity
pm2 logs trigger-proxy --lines 50
pm2 restart trigger-proxy       # reload after config change
```

## Integration with n8n

In the n8n `TaskApproved` workflow, the **Trigger Agent Session** HTTP Request node POSTs to `http://172.18.0.1:5679/` with:

- `X-Trigger-Secret` header — stored as an n8n credential
- JSON body — `trigger_id` looked up from a switch node keyed on `target_agent`, `task_id` from the approved task payload

The workflow uses `trigger_id` values that correspond to the entries in `trigger-map.yml`. If you add a new agent variant, update both the trigger-map and the n8n switch node.

## Logs

Each request logs: ISO timestamp, source IP, `trigger_id`, `target_agent`, `task_id`, and response status code. Failed upstream calls include the HTTP status from the Anthropic API.

```bash
# Check for failed triggers
grep -i "error\|502\|403" ~/.pm2/logs/trigger-proxy-error.log
```

## Gotchas and Lessons Learned

**Initial design had no auth beyond bridge binding.** The first version relied solely on the bridge network address to restrict access — any of the 29 containers on `claudebox-net` could call the proxy. The `X-Trigger-Secret` header was added in the security hardening pass to limit access to containers that have the secret (n8n, which stores it as a credential). Both controls now apply.

**Token refresh writes back to credentials.json.** The proxy has write access to `~/.claude/.credentials.json`. This is intentional — a refreshed token must be persisted or it will be lost on the next request. The file is kept at `0600`; do not relax permissions.

**PM2 must export the secret to the process env.** `TRIGGER_PROXY_SECRET` is read from `os.environ` at startup. If the PM2 ecosystem config is redeployed without the env var set, the proxy will fail to start (it validates the secret exists on init). Check `pm2 env trigger-proxy` to confirm the variable is present.

---

## Related Docs

- [n8n](n8n.md) — workflow engine that calls trigger-proxy on task approval
- [Task Dispatcher](task-dispatcher.md) — posts approved-task webhooks that drive n8n → trigger-proxy
- [Agent Orchestration](agent-orchestration.md) — agent manifests and trigger-map.yml schema
- [Architecture](../architecture.md) — autonomous pipeline data flow
