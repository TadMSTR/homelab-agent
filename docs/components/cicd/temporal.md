# Temporal (retired 2026-10-25)

Temporal was a durable workflow execution engine intended to drive autonomous, multi-step
agent build pipelines. It ran as a Docker stack (server, PostgreSQL backend, web UI) with a
PM2-managed `temporal-build-worker` that turned workflow activities into agent tasks.

## Retirement

Retired 2026-10-25 under the `service-retirement-2026-10` build, part of a sweep that removed
unused code and stacks before a code-review baseline. The reasons:

- **No workflow was ever run** through it in production.
- **It duplicated existing machinery.** The build skills and task-dispatcher's `auto` mode
  already sequence multi-step builds.
- **It bypassed the task queue's validation.** The worker wrote YAML task files straight into
  the queue directory instead of going through [task-queue-mcp](../agent/task-queue-mcp.md),
  and those files used a long-outdated schema.

The stack was brought down, its appdata archived to the NAS (TLS private keys deleted, not
archived), its volumes removed, and the SWAG route, Homepage tile, worker process, helper
scripts and the worker's Vault AppRole deleted. The worker's source repo is being archived.

There is no replacement workflow engine. Multi-step builds run through the build skills
(`shared-build-review` → build → `shared-build-pre-audit` → `shared-build-finalize`) and
[task-dispatcher](../agent/task-dispatcher.md).

## What it was

- **Images:** `temporalio/server`, `temporalio/ui`, `temporalio/admin-tools` (one-shot schema
  init and namespace creation), `postgres:16` (databases `temporal` and `temporal_visibility`)
- **Endpoints:** gRPC frontend on `127.0.0.1:7233` (localhost-only); web UI behind SWAG and
  Authentik forward auth at `temporal.example.com`
- **mTLS:** required on the frontend (`requireClientAuth: true`); the worker pulled its client
  certificates from Vault via AppRole
- **Consumers:** `temporal-build-worker` (PM2) and a task-dispatcher route for
  `task_type: workflow`; no MCP server
- **Hardening:** `cap_drop: ALL`, `no-new-privileges`, memory limits, a custom entrypoint that
  substituted the PostgreSQL password into the config template at startup

## Related Docs

- [task-dispatcher.md](../agent/task-dispatcher.md) — current task routing and auto-launch
- [task-queue-mcp.md](../agent/task-queue-mcp.md) — the validated task write path
