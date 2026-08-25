# AGENTS.md — homelab-agent

Public reference repository documenting the homelab-agent platform — a multi-agent AI homelab built on Claude Code running on forge. Covers the full three-layer architecture: dedicated host, self-hosted Docker service stack, and a five-agent Claude Code engine with scoped tool surfaces, persistent memory, and Matrix-based dispatch.

## Purpose

This repo has two audiences: humans learning to build a similar platform, and AI agents navigating the docs to assist with homelab tasks.

- **For humans:** Start with `README.md`, then `docs/phases/` for the build narrative. Stop at any layer — each is independently useful.
- **For AI agents:** Use `docs/components/` for per-service operational context. The `manifests/` directory has sanitized examples of agent configuration.

## Resident Agents

Five agents run as scoped Claude Code projects on forge. Each has a dedicated Matrix room and a manifest that defines its tool surface.

| Agent | Role | Matrix Room | Key Tools |
|-------|------|-------------|-----------|
| `sysadmin` | Infrastructure ops — Docker updates, apt patching, service diagnostics | its own room (`MATRIX_ROOM_SYSADMIN`) | system-ops, dockhand-mcp, patchmon-mcp, pm2-mcp, githost-mcp |
| `research` | Research and build planning — upstream docs, architecture decisions, handoffs | `#research:` | searxng-mcp, qmd, githost-mcp, task-queue-mcp |
| `developer` | Code — MCP servers, scripts, config changes, PRs | `#developer:` | system-ops, githost-mcp, task-queue-mcp, signoz-mcp |
| `writer` | Documentation — READMEs, runbooks, component docs, public repo updates | `#writer:` | system-ops, githost-mcp, qmd, task-queue-mcp |
| `security` | Security audits, triage reports, remediation verification | `#security:` | system-ops, githost-mcp, searxng-mcp, signoz-mcp |

## scoped-mcp Architecture

Each agent's tool surface is controlled by a manifest file. [scoped-mcp](docs/components/agent/scoped-mcp.md) reads the manifest and proxies only the allowed tools — agents never hold credentials directly.

```
operator message → Matrix room → matrix-dispatcher → agent project dir
                                                           ↓
                                          scoped-mcp reads manifest
                                                           ↓
                                     agent ↔ MCP proxy ↔ backend service
```

Sanitized manifest examples are in [`manifests/`](manifests/). The full manifest schema is documented in [`docs/components/agent/scoped-mcp.md`](docs/components/agent/scoped-mcp.md).

## Recent Agent Framework Changes

- **HITL interactive-mode contract (2026-07-21):** scoped-mcp v1.11.0 added an
  `hitl.mode: interactive` option, currently enabled for the developer and sysadmin
  manifests. Under this contract the operator can verbally authorize a gated action in
  the same conversation, and the agent self-approves the HITL gate rather than requiring
  a separate out-of-band CLI approval step. See
  [`docs/components/agent/scoped-mcp.md`](docs/components/agent/scoped-mcp.md) for the
  gate mechanics.
- **Graphiti "Read when" companion section (2026-07-25):** every resident agent's
  CLAUDE.md now carries a "Read when" companion section alongside its Graphiti write
  guidance — short rules of thumb for when to query the knowledge graph (relational,
  temporal questions) versus flat memory notes (session/working detail), so agents don't
  default to one at the expense of the other.
- **githost-mcp per-agent launchers (v0.5.0):** each of the six agent manifests
  (developer, sysadmin, research, security, writer, harlock) launches its own
  githost-mcp process via a dedicated per-agent launcher script and env file, rather
  than sharing one process — giving each agent its own `ALLOWED_REPO_ROOTS` scope and
  clean per-agent attribution in the audit log. See
  [`docs/components/mcp-servers/githost-mcp.md`](docs/components/mcp-servers/githost-mcp.md).

## Key Docs

- `README.md` — Architecture overview, layer descriptions, component tables
- `docs/phases/` — Build history (read in order for the full build narrative)
- `docs/components/` — Per-component operational reference (76 docs)
- `docs/operations/` — Runbooks for common operational tasks
- `manifests/` — Sanitized agent manifest examples
- `claude-code/` — Claude Code project configs (CLAUDE.md examples per agent)
- `docker/` — Docker Compose stacks with `.env.example` templates
- `pm2/` — PM2 ecosystem config and process documentation

## Conventions

- **Sanitized for public use** — Internal IPs, credentials, and room IDs are replaced with placeholders. Component docs describe real architecture but use generic values.
- **Layer attribution** — Each component doc includes which layer it belongs to (Layer 1/2/3) and its dependencies.
- **One doc per component** — Cross-references via links, not duplication.
- **`.env.example` not `.env`** — All docker/ stacks ship with example env files only. No real values are committed.

## What Not to Change Without Discussion

- Sanitization policy — Public repo. No real IPs, tokens, room IDs, or personally identifying paths.
- Layer categorization — Misclassifying a component confuses the build narrative in docs/phases/.
