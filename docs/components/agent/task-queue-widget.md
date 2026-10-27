# task-queue-widget (retired 2026-10-25)

task-queue-widget was a React + TypeScript dashboard for the forge task queue, served as a
static nginx build and embedded in Matrix as an Element widget. It had no backend of its own:
task actions went out as custom Matrix room events, which
[matrix-task-queue-bot](matrix-task-queue-bot.md) handled.

## Retirement

Retired 2026-10-25 under the `service-retirement-2026-10` build — it was unused. The
`task-queue-widget` service and its `widget-internal` network were dropped from the
task-queue-mcp compose stack (task-queue-mcp itself is unchanged and stayed up throughout),
the SWAG `widgets` subdomain route was removed, and the image deleted. The source repo is
being archived.

Task queue visibility now comes from the CloudCLI plugin and from matrix-task-queue-bot's
pinned per-agent status boards and daily morning brief.

## What it was

- **Container:** nginx serving the static build, `user: 101:101`, `cap_drop: ALL`,
  `no-new-privileges`, 128 MB / 0.5 CPU limits
- **Exposure:** loopback port proxied by SWAG at `widgets.example.com`, behind Authentik
  forward auth
- **Networks:** `widget-internal` (`internal: true`) and `forge-net`
- **Configuration:** none at runtime — baked into the build

## Related Docs

- [matrix-task-queue-bot.md](matrix-task-queue-bot.md) — Matrix client of the task queue
- [task-queue-mcp.md](task-queue-mcp.md) — task queue MCP server and HTTP API
