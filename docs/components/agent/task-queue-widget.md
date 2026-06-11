# task-queue-widget

React + TypeScript web widget for the forge task queue dashboard. Runs as a Docker
container serving a static nginx build, embedded in Matrix via Element widgets.
Communicates with the matrix-task-queue-bot through Matrix room events only.

## Service

| Field | Value |
|-------|-------|
| Container | `task-queue-widget` |
| Image | Built from `~/repos/personal/matrix-task-queue-widget` |
| Stack | `~/docker/task-queue-widget/` |
| Port | `127.0.0.1:8497 → 8080` (proxied via SWAG) |
| Public URL | `https://widgets.helmforge.me` |
| Auth | Authentik forward auth |
| Network | `widget-internal`, `forge-net` |

## Configuration

The widget is a static React build served by nginx. No runtime env vars — configuration
is baked at build time from the source repo.

## Security

- Runs as `user: 101:101` (nginx user in Alpine)
- `cap_drop: ALL`, `security_opt: no-new-privileges:true`
- Memory limit: 128 MB, CPU limit: 0.5 cores
- `widget-internal` network is marked `internal: true`

## Dependencies

- **matrix-task-queue-bot** — handles backend logic via Matrix room events
- **SWAG** — reverse proxy at `widgets.helmforge.me`
- **Authentik** — forward auth
- **Matrix / Synapse** — event transport between widget and bot

## Operations

```bash
# Check container status
docker ps -f name=task-queue-widget

# View logs
docker logs task-queue-widget --tail 50

# Rebuild after source changes
cd ~/docker/task-queue-widget && docker compose build && docker compose up -d
```

## Related Docs

- [matrix-task-queue-bot.md](matrix-task-queue-bot.md) — backend bot service
- [task-queue-mcp.md](task-queue-mcp.md) — task queue MCP server
