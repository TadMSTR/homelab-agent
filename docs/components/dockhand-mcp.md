# dockhand-mcp

FastMCP Python MCP server wrapping the [Dockhand](https://github.com/Finsys/dockhand)
REST API. Gives forge's operator agents structured access to Docker container and stack
management: listing, lifecycle actions, image update checking, pulling, CVE scanning, and
activity log access.

- **Source:** `~/repos/personal/dockhand-mcp/`
- **PM2 service:** `dockhand-mcp` (forge, stdio transport)
- **Status:** Phase 3 forge deployment in progress (helm-build)
- **Version:** 0.1.0
- **Dockhand version verified:** v1.0.27

## Tools

| Tool | Description |
|------|-------------|
| `get_health` | Dockhand health status and timestamp |
| `list_containers` | All containers: name, image, status, environment |
| `list_stacks` | All Compose stacks: name, status, container count |
| `container_action` | start / stop / restart / pause / unpause / remove a container |
| `stack_action` | start / stop / restart / deploy a stack |
| `check_updates` | Queue an async image update check for all containers |
| `update_container` | Pull latest image and recreate a specific container |
| `scan_image` | Trivy/Grype CVE scan by image name |
| `get_activity` | Recent Dockhand operations log |

## Container Actions

`container_action` accepts: `start`, `stop`, `restart`, `pause`, `unpause`, `remove`.
`stack_action` accepts: `start`, `stop`, `restart`, `deploy`.

`deploy` pulls new images and recreates the stack — equivalent to
`docker compose up -d --pull`. Use for image updates on a full stack rather than a
single container.

## Update Workflow

```
1. check_updates()
   → queues async job; get_activity() to see when it completes

2. list_containers()
   → check which containers show update available

3. scan_image("nginx:latest")
   → review CVE count before pulling

4. update_container(container_id)
   → pulls latest image and recreates the container
```

`check_updates` is async — it queues a job and returns immediately. Poll `get_activity()`
to confirm when the check is complete before relying on update-available flags.

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `DOCKHAND_ENDPOINT` | yes | — | Base URL, e.g. `http://localhost:7777` |
| `DOCKHAND_API_TOKEN` | yes | — | Bearer token from Dockhand UI (Settings → API Tokens) |
| `DOCKHAND_DEFAULT_ENV` | no | — | Default environment ID. Required for `update_container` if not passed explicitly |
| `LOG_LEVEL` | no | `INFO` | structlog verbosity |
| `LOG_FILE` | no | — | Log to file path; stdout if unset |
| `INFLUXDB_URL` | no | — | Enables InfluxDB telemetry when set |
| `INFLUXDB_TOKEN` | no | — | InfluxDB auth token |
| `INFLUXDB_BUCKET` | no | `dockhand-mcp` | InfluxDB bucket name |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | — | Enables OTEL traces when set |
| `NATS_URL` | no | — | Enables NATS event publishing when set |
| `NATS_SUBJECT_PREFIX` | no | `dockhand` | NATS subject prefix |

Secrets are injected at PM2 startup via `--env-file ~/.secrets/forge.env`.

**Getting the environment ID:**
```bash
curl -s http://localhost:7777/api/environments \
  -H "Authorization: Bearer <token>" | python3 -m json.tool
```
The forge environment has `"id": 1`. Set `DOCKHAND_DEFAULT_ENV=1` in forge.env.

## Deployment

```bash
cd ~/repos/personal && git clone <repo-url> dockhand-mcp
cd dockhand-mcp
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# Create API token: Dockhand UI → Settings → API Tokens
# Add DOCKHAND_API_TOKEN to ~/.secrets/forge.env

pm2 start ecosystem.config.js --env-file ~/.secrets/forge.env
pm2 save
```

## Observability

| Feature | Default | Enable with |
|---------|---------|-------------|
| Structured JSON logging | **ON** | `LOG_LEVEL`, `LOG_FILE` |
| InfluxDB telemetry | off | `INFLUXDB_URL` |
| OTEL traces | off | `OTEL_EXPORTER_OTLP_ENDPOINT` |
| NATS publishing | off | `NATS_URL` |

## Security

From build audit (3 findings, all resolved):

| ID | Finding | Resolution |
|----|---------|------------|
| — | SSH remote in git config exposed internal hostname | Switched to HTTPS remote before publish |
| — | Path traversal in file-serving utility | Input validation guard added |
| — | Query parameter encoding not sanitised | Proper URL encoding applied |

API endpoint paths were verified against a live Dockhand v1.0.27 instance via SvelteKit
manifest extraction from the running container before implementation.

## Related Docs

- [dockhand.md](dockhand.md) *(if exists)* — the Dockhand service this wraps
- [patchmon-mcp.md](patchmon-mcp.md) — companion apt patch management MCP
- [renovate.md](renovate.md) — companion non-Docker update scanner
