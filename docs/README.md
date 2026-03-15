# Documentation

Detailed documentation for the homelab-agent platform. Start with the [main README](../README.md) for the architecture overview and origin story — these docs go deeper.

## Where to Start

- **[Getting Started](getting-started.md)** — Dependency-ordered setup guide with five natural stopping points. Read this if you want to build the stack.
- **[Architecture](architecture.md)** — Data flows, network topology, security model, and scaling considerations. Read this if you want to understand how the pieces connect.
- **[Architecture Decisions](decisions.md)** — Consolidated rationale behind major architectural choices. Read this if you want to understand *why* specific tools were chosen.

## Component Docs

Per-component deep dives live in [`components/`](components/). Each doc covers what the component does, why it's in the stack, how to configure it, and gotchas from running it in production. See the [components README](components/README.md) for the full list.

## Examples

End-to-end workflow walkthroughs with sanitized placeholder values in [`examples/`](examples/).

- **[Security Audit Workflow](examples/security-audit-workflow.md)** — Building agent writes a completion report → security agent runs audit → triage → action plan routed back to building agent.

## Other References

These live in the repo root, not in `docs/`:

- [`mcp-servers/README.md`](../mcp-servers/README.md) — MCP server reference with config patterns and adoption path
- [`claude-code/`](../claude-code/) — CLAUDE.md templates and per-agent project configs
- [`pm2/ecosystem.config.js.example`](../pm2/ecosystem.config.js.example) — PM2 service and cron definitions
- [`docker/`](../docker/) — Sanitized Docker Compose files for every stack
- [`scripts/`](../scripts/) — Utility scripts (backups, monitoring, reindexing)
