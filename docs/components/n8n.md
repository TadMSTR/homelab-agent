# n8n

n8n is a visual workflow automation engine. In this stack it handles webhook-triggered task routing alongside the PM2-based task dispatcher — receiving task submissions via webhook, applying risk-based approval gating, and sending alert notifications. It runs as a Docker container backed by Postgres for workflow and credential storage.

The immediate use is replacing the dispatcher's hardcoded routing logic with editable visual workflows. Instead of modifying Python code to change how tasks are routed or what triggers a notification, you edit a workflow in n8n's browser UI. The file-based task queue remains the source of truth; n8n is a routing and automation layer on top of it.

## Why n8n

The PM2 task dispatcher (`task-dispatcher.py`) works well for polling the queue and managing task lifecycle, but its routing logic is baked into Python code. Adding a new routing rule — say, "if task_type is `deploy` and target is `atlas`, also notify the Slack channel" — means editing the script, testing, and restarting PM2. n8n makes this kind of change a drag-and-drop operation in a browser.

n8n was chosen over:
- **Node-RED** — better for IoT and device control; n8n's trigger/action model is a cleaner fit for webhook-driven task routing
- **Huginn** — powerful but Ruby-based and heavier; n8n is more actively maintained and has broader integration coverage
- **Custom webhook server** — less work upfront, but loses the visual workflow editor and pre-built integrations

n8n's self-hosted model keeps everything local — no data leaves the host unless a workflow explicitly calls an external API.

## How It Works

n8n runs two containers on `claudebox-net`: the workflow engine and a Postgres database.

**Ports:**
- `5678` — n8n web UI and webhook endpoint (localhost-only, proxied at `n8n.yourdomain`)

**Appdata:**
- `/opt/appdata/n8n/data/` — workflow definitions, credentials, encryption keystore
- `/opt/appdata/n8n/postgres/` — PostgreSQL data directory

### Volume Mounts

n8n has direct filesystem access to the task queue and agent registry:

| Mount | Container Path | Access | Purpose |
|-------|---------------|--------|---------|
| `~/.claude/task-queue/` | `/task-queue/` | read-write | Read submitted tasks, write results |
| `~/.claude/agent-manifests/` | `/agent-manifests/` | read-only | Read agent capabilities for routing decisions |

This means n8n workflows can read task YAML files and agent manifests natively using the "Read Binary File" or "Execute Command" nodes — no API intermediary needed.

### Task Dispatcher Workflow

The primary workflow (`Task Dispatcher`, webhook ID: `task-submitted`) implements risk-based routing:

```
POST /webhook/task-submitted
  │
  ├── Parse Task (extract task_id, summary, risk_level, target_agent, ...)
  │
  └── Risk Gate
        ├── high risk OR requires_approval → ntfy alert → respond 200
        └── low risk → no-op → respond 200
```

The dispatcher posts task submissions to this webhook endpoint. The workflow parses the task payload, checks the risk level, and routes accordingly:
- **High-risk tasks** trigger an ntfy push notification with the task summary, risk level, source agent, and task ID
- **Low-risk tasks** pass through silently (the file queue handles actual task delivery to agents)

Both paths return HTTP 200 to the caller — the webhook is fire-and-forget from the dispatcher's perspective.

### Workflow Management

Workflows are managed through n8n's web UI at `n8n.yourdomain` or via the REST API:

```bash
# List all workflows
curl -s http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq '.data[].name'

# Export a workflow (for version control)
curl -s http://localhost:5678/api/v1/workflows/H4kYuvEdeizAG2JI \
  -H "X-N8N-API-KEY: $N8N_API_KEY" | jq > ~/docker/n8n/workflows/task-dispatcher.json

# Import/update a workflow from file
curl -X PUT http://localhost:5678/api/v1/workflows/H4kYuvEdeizAG2JI \
  -H "X-N8N-API-KEY: $N8N_API_KEY" \
  -H "Content-Type: application/json" \
  -d @~/docker/n8n/workflows/task-dispatcher.json
```

Exported workflow JSON files are stored in `~/docker/n8n/workflows/` and version-controlled alongside the compose file.

## Configuration

**Docker Compose:** `~/docker/n8n/docker-compose.yml`

**Environment (`.env`):**

| Variable | Purpose |
|----------|---------|
| `DB_USER` / `DB_PASSWORD` | Postgres credentials (shared by both containers) |
| `N8N_ENCRYPTION_KEY` | Encrypts credentials stored in the database — **non-recoverable if lost** |
| `WEBHOOK_URL` | Public URL for webhook callbacks (`https://n8n.yourdomain/`) |
| `N8N_HOST` | Hostname for the web UI |
| `GENERIC_TIMEZONE` | Timezone for workflow scheduling |
| `N8N_DIAGNOSTICS_ENABLED` | Set `false` — disables telemetry |

**SWAG proxy:** `n8n.subdomain.conf` — proxies port 5678 with SSL termination. n8n uses its own built-in auth (email/password) rather than Authelia — this is intentional because webhook endpoints need to be reachable without SSO session cookies. Authelia can be layered on top if needed.

**Auth note:** The SWAG proxy deliberately omits Authelia because n8n's webhook endpoints (`/webhook/*`) must accept unauthenticated POST requests from internal callers (the task dispatcher). Adding Authelia would require carving out exceptions for webhook paths, which adds complexity for minimal security gain on an internal-only domain.

## Integration Points

**task-dispatcher.py:** The PM2 dispatcher posts task submissions to n8n's webhook endpoint (`POST /webhook/task-submitted`) when the `N8N_WEBHOOK_URL` environment variable is set. The post is fire-and-forget — if n8n is down, the dispatcher logs a warning and continues operating normally. The file queue handles task routing regardless of n8n's availability.

**NATS JetStream:** n8n and NATS serve complementary roles. NATS provides pub/sub event streaming for task lifecycle transitions (observability); n8n provides webhook-triggered workflow execution (routing and automation). They don't depend on each other — either can be removed without affecting the other or the core task queue.

**ntfy:** The task dispatcher workflow sends push notifications for high-risk tasks via ntfy. The notification includes the task summary, risk level, target agent, and task ID — enough context to approve or investigate from a phone.

**Backup and restore:** The `N8N_ENCRYPTION_KEY` is backed up to NFS secrets storage and restored by `deploy-claudebox.sh`. Without the original encryption key, any credentials stored in n8n's database become unreadable after restore. The deploy script has explicit handling for this — see [claudebox-deploy.md](claudebox-deploy.md).

## Gotchas and Lessons Learned

**The encryption key is the most critical secret.** `N8N_ENCRYPTION_KEY` encrypts all credentials stored in n8n's Postgres database. If you lose it, every credential (API keys, tokens, passwords stored in n8n) becomes unrecoverable. Back it up separately from the container data. The deploy script restores it from `${NFS_DOCKER_SECRETS}/n8n.env`.

**n8n has its own user auth.** Unlike most services in this stack, n8n doesn't use Authelia for authentication. It has built-in email/password auth with optional 2FA. This is necessary because webhook endpoints need to accept unauthenticated requests from internal services.

**Workflow exports are not automatic.** When you modify a workflow in the n8n UI, the change lives in the Postgres database. To version-control it, you need to export it via the API (see the curl commands above) and commit the JSON to `~/docker/n8n/workflows/`. Consider exporting after any significant workflow change.

**The webhook URL must match the SWAG proxy.** `WEBHOOK_URL` in `.env` tells n8n what its externally-reachable base URL is. If this doesn't match the SWAG proxy config, webhook registrations and callback URLs will be wrong. Both should point to `https://n8n.yourdomain/`.

**Postgres healthcheck gates n8n startup.** The compose file uses a Postgres healthcheck with `service_healthy` dependency. If Postgres fails its readiness check (5 retries, 10s interval), n8n won't start. Check `docker logs n8n-db` first if n8n appears stuck.

## Standalone Value

n8n is useful beyond task routing. Any webhook-driven automation — GitHub webhook handlers, scheduled data collection, API integrations, notification pipelines — can run as an n8n workflow without writing code. The task dispatcher integration is just the first workflow; the platform is general-purpose.

If you're building the agent orchestration system and want to start simple, the PM2 dispatcher handles everything without n8n. Add n8n when you want visual workflow editing, or when your routing logic gets complex enough that editing Python feels slower than dragging nodes in a browser.

## Further Reading

- [n8n documentation](https://docs.n8n.io/)
- [n8n self-hosting guide](https://docs.n8n.io/hosting/)
- [n8n API reference](https://docs.n8n.io/api/)

---

## Related Docs

- [Agent Orchestration](agent-orchestration.md) — the task queue and dispatcher that posts to n8n's webhook
- [NATS JetStream](nats-jetstream.md) — complementary event bus for task lifecycle observability
- [claudebox-deploy](claudebox-deploy.md) — deploy script with n8n encryption key restore
- [Architecture overview](../../README.md#layer-3--multi-agent-claude-code-engine) — Layer 3 context
