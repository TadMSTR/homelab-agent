# Forge — Agent Setup

**Completed:** 2026-05-25
**Snapshots:** pre-forge-agent-setup (in `/.snapshots/`)

## What Was Built

Bootstrapped the 5 forge resident agents (sysadmin, research, developer, writer, security)
as fully wired Claude Code sessions with scoped tool surfaces. This build wires together
all the infrastructure deployed in prior builds: scoped-mcp, patchmon-mcp, dockhand-mcp,
langfuse-mcp, and homelab-ops-mcp are now connected to each agent via per-agent manifests.

It also unblocks matrix-dispatcher: the 5 agent project directories now exist, so
matrix-dispatcher can route messages to live agent sessions.

## What Was Set Up

| Agent | Project dir | CLAUDE.md committed |
|-------|-------------|---------------------|
| sysadmin | `~/.claude/projects/sysadmin` | agent-platform/agents (commit `68bdd7a`) |
| research | `~/.claude/projects/research` | agent-platform/agents (commit `68bdd7a`) |
| developer | `~/.claude/projects/developer` | agent-platform/agents (commit `68bdd7a`) |
| writer | `~/.claude/projects/writer` | agent-platform/agents (commit `68bdd7a`) |
| security | `~/.claude/projects/security` | agent-platform/agents (commit `68bdd7a`) |

Project symlinks created on forge pointing each agent's project directory to the correct
Claude Code project path.

## scoped-mcp Manifest Wiring

Each agent has a manifest at `~/.claude/manifests/<agent>-agent.yml` (YAML). All 5
manifests use `mcp_proxy` module type to route tool calls to forge's MCP services.
See [scoped-mcp.md](../components/agent/scoped-mcp.md) for the current full tool
surface per agent — scope has evolved significantly since initial setup.

Initial wiring at build time:

| MCP service | Module name | Initial scope |
|-------------|------------|---------------|
| patchmon-mcp | `patchmon` | sysadmin only |
| dockhand-mcp | `dockhand` | sysadmin only |
| langfuse-mcp | `langfuse` | research, developer |
| homelab-ops-mcp | `system-ops` | All 5 agents |
| matrix-mcp | `matrix` | All 5 agents |

## Gitea SSH Configuration

Gitea on forge runs SSH on **port 2222** (non-standard). The forge `~/.ssh/config`
handles this transparently for all git operations:

```
Host gitea.tadmstr.me
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
```

CLAUDE.md files for the 5 agents were committed to `agent-platform/agents` on Gitea
via this SSH config.

## scoped-mcp Dependency Fixes

scoped-mcp v1.0.0 is pre-installed at `/opt/venvs/scoped-mcp/`. Two missing
dependencies were discovered during agent startup and installed:

- `aiosmtplib` — async SMTP client (required by scoped-mcp core)
- `aiosqlite` — async SQLite adapter (required by audit log module)

These are now present in the venv. If the venv is rebuilt, ensure both are installed.

## Security Audit Remediation

Two `.bashrc` shell hygiene fixes applied as part of audit remediation:

1. Removed a leftover inline secret from `.bashrc` (rotated credential, no longer valid)
2. Tightened PATH export to remove a redundant entry that could shadow system binaries

## matrix-dispatcher Unblocked

The `forge-agent-setup` build was the listed prerequisite for wiring
`matrix-dispatcher`'s `project_dirs`. With all 5 project directories now provisioned,
the matrix-dispatcher config.yml can be updated with real paths and the PM2 service
restarted. Follow-up task for helm-build.

## Post-Build Follow-Ups (completed)

- Per-agent `MATRIX_ACCESS_TOKEN` generated; matrix module added to all 5 manifests
- `matrix-dispatcher` config.yml updated with real project paths; PM2 service restarted
- Phase 7 hardening applied (denylists, rate limits, HITL, audit, argument/response filters) — see scoped-mcp.md

## Related Docs

- [scoped-mcp.md](../components/agent/scoped-mcp.md) — forge scoped-mcp deployment
- [phase-matrix-synapse.md](phase-matrix-synapse.md) — Matrix homeserver (forge)
- [forge-operator-agents.md](forge-operator-agents.md) — prior phase: MCP services deployed
