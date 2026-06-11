# Forge — Matrix Agent Wiring

**Completed:** 2026-05-25
**Snapshots:** (none — config-only build)

## What Was Built

Completed the last missing piece of the agent framework: per-agent Matrix access tokens
and scoped-mcp matrix module wiring. All 5 forge resident agents (sysadmin, research,
developer, writer, security) now have Matrix bot accounts authenticated via individual
access tokens, with per-agent room scoping in their scoped-mcp manifests. The
matrix-dispatcher config was updated with the correct agent names and project directories,
unblocking Matrix → agent routing end-to-end.

## Sub-Phases

### Phase 1 — Per-Bot Access Token Generation

Each agent's bot account received an access token via the Matrix client login API.
Tokens were generated using curl against the Synapse homeserver with each bot's
username/password credentials from `~/.secrets/matrix-forge.env`:

```bash
curl -s -X POST 'https://matrix.helmforge.me/_matrix/client/r0/login' \
  -H 'Content-Type: application/json' \
  -d '{"type":"m.login.password","user":"@<bot>:helmforge.me","password":"<pass>"}'
```

Each token is unique to its bot account and stored in the per-agent `settings.json`.

### Phase 2 — scoped-mcp Matrix Module Config

The matrix module was added to each agent's manifest at `~/.claude/manifests/<agent>.json`.
Room access is scoped per agent — each agent can only reach its own room and the shared
announcements room:

| Agent | Allowed rooms |
|-------|--------------|
| sysadmin | `#sysadmin:helmforge.me`, `#announcements:helmforge.me` |
| research | `#research:helmforge.me`, `#announcements:helmforge.me` |
| developer | `#developer:helmforge.me`, `#announcements:helmforge.me` |
| writer | `#writer:helmforge.me` _(no announcements — docs-only agent)_ |
| security | `#security:helmforge.me`, `#announcements:helmforge.me` |

### Phase 3 — MATRIX_ACCESS_TOKEN Delivery via settings.json

`MATRIX_ACCESS_TOKEN` for each agent is delivered via `settings.json` env blocks rather
than `forge.env`. This is required because scoped-mcp reads its config from the Claude
Code settings file, not the parent shell environment. Each agent's settings.json at
`~/.claude/projects/<agent>/settings.json` contains:

```json
{
  "env": {
    "MATRIX_ACCESS_TOKEN": "<bot-specific-token>"
  }
}
```

Files are `chmod 600` (owner-read-only) and not tracked in git.

### Phase 4 — matrix-dispatcher Config Update

The matrix-dispatcher `config.yml` `project_dirs` section was populated with all 5 real
agent project directory paths. The key name `dev` was corrected to `developer` to match
the actual agent name and project directory:

```yaml
project_dirs:
  sysadmin: /home/ted/.claude/projects/sysadmin
  research: /home/ted/.claude/projects/research
  developer: /home/ted/.claude/projects/developer   # was "dev" — corrected
  writer: /home/ted/.claude/projects/writer
  security: /home/ted/.claude/projects/security
```

The PM2 matrix-dispatcher service (id 21) was restarted to pick up the config change.
The `config.forge.yml` backup file was also updated to match (L2 security fix below).

## Security Audit Results

3 Low findings, all resolved.

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| L1 | Low | `renovate-bot_PAT` uses a hyphen — invalid shell variable name, breaks `set -o allexport` sourcing in strict mode | Renamed to `RENOVATE_BOT_PAT` in `~/.secrets/forge.env`; single reference updated |
| L2 | Low | `config.forge.yml` still had stale `dev:` key and non-existent project path after the dev→developer rename | Updated to match `config.yml` (key renamed, path corrected) |
| L3 | Low | matrix-dispatcher `config*.yml` files at 664 (world-readable) — exposes homeserver URL, bot MXIDs, room IDs | `chmod 640` applied to all three config files |

No commits — all touched files are non-git-tracked secrets or local config files.

## Known Gaps at Completion

- **GITEA_TOKEN** for the sysadmin agent: needed for Gitea API calls, not yet provisioned.
  SSH-based git operations work in the interim.
- **agent-bus wiring**: deferred to Phase 7 hardening (research task 0fb2f48f).

## Related Docs

- [forge-agent-setup.md](forge-agent-setup.md) — prior phase: agent project dirs and manifests
- [phase-matrix-synapse.md](phase-matrix-synapse.md) — Matrix homeserver (Synapse + PostgreSQL)
- [matrix-dispatcher.md](../components/agent/matrix-dispatcher.md) — matrix-dispatcher on forge
- [forge-agent-mcp-restore.md](forge-agent-mcp-restore.md) — next phase: scoped-mcp repair and observability
