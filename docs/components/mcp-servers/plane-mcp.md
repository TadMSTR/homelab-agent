# plane-mcp (retired 2026-10-25)

plane-mcp was a FastMCP server (the upstream `plane-mcp` PyPI package) wrapping the Plane
project management API. It ran as a PM2 process on a loopback streamable-http port and was
proxied to agents through scoped-mcp, with a per-agent Plane API token injected as a request
header and validated against Plane before each request.

## Retirement

Retired 2026-10-25 under the `service-retirement-2026-10` build. Forge moved its issue
tracking from Plane to [Vikunja](../apps/vikunja.md) on 2026-07-19, and by the time of the
retirement only one agent manifest still listed the module. The PM2 app, its launcher, every
scoped-mcp manifest module, and the Plane helper scripts (project bootstrap, label creation,
ticket backfill, state standardization, token rotation) were removed.

The Plane server itself is **parked**, not retired — see [plane.md](../apps/plane.md). If it is
started again for the migration gap-fill, the gap-fill tool talks to Plane's REST API
directly; plane-mcp is not needed and is not coming back.

Ticket work now goes through [vikunja-mcp](vikunja-mcp.md).

## What it was

- **Transport:** streamable-http on a loopback port, managed by PM2
- **Auth:** `Authorization: Bearer <token>` plus an `x-workspace-slug` header, injected per
  agent by scoped-mcp; a `PlaneTokenValidator` middleware checked each token against Plane's
  `/api/v1/users/me/` before FastMCP handled the request
- **Tool surface:** the full upstream set — projects, work items, epics, cycles, modules,
  milestones, initiatives, intake, labels, states, comments/links/relations/work logs, work
  item types and properties, pages, workspace members
- **Access:** per-agent tool allowlists in the scoped-mcp manifests (read + create for most
  agents, full access for the build agents)

## Related Docs

- [plane.md](../apps/plane.md) — the parked Plane stack
- [vikunja.md](../apps/vikunja.md) — the current tracker
