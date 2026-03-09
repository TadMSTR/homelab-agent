# Homelab Operations Agent

Focus: Infrastructure management, Docker stacks, monitoring, backups, networking.

## Available MCP Tools

List the MCP servers this agent should use. This tells Claude Code what tools are
available for this domain of work.

Example (adapt to your setup):

- Netdata: your-host (localhost:19999), other-host (192.168.1.x:19999)
- Grafana MCP (dashboards, alerts, Loki logs, InfluxDB queries)
- Unraid MCP (array status, disk health, Docker containers — read-only API key)
- TrueNAS MCP (datasets, pools, snapshots)
- InfluxDB MCP (time-series queries, buckets per host)

## Key Infrastructure

Summarize what this agent needs to know. This is domain-specific context that
supplements the root CLAUDE.md.

Example:

- Server1: 77+ containers, 150TB array, ZFS appdata
  - Runs SWAG (your-domain.com, external-facing proxy)
- Server2: TrueNAS, 25 containers, 87TB ZFS (RAIDZ2), Dockhand-managed
  - Runs SWAG (internal domain), InfluxDB, Grafana, Loki, ntfy
- AI Host: Local Docker (SWAG + chat UI), PM2 services
- 10GbE backbone between storage hosts
- Backups: appdata → backup server (nightly), Docker stacks → Backrest

## Memory

- Read from: ~/.claude/memory/shared/, ~/.claude/memory/agents/homelab-ops/
- Write to: ~/.claude/memory/agents/homelab-ops/
- For cross-agent knowledge, write to ~/.claude/memory/shared/

## Conventions

- Always verify changes with health checks after applying.
- Log infrastructure changes to memory with date and rationale.
- Reference compose file repo for Docker stack definitions.
