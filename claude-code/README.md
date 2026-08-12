# Claude Code Configuration

Example Claude Code project configurations for the homelab-agent platform's five resident agents. These show how each agent is scoped, what tools it uses, and how sessions are structured.

## Files

```
claude-code/
├── CLAUDE.md.example           — Root context file (~/.claude/CLAUDE.md)
└── projects/
    ├── sysadmin.md.example     — Sysadmin agent project config
    ├── research.md.example     — Research agent project config
    ├── developer.md.example    — Developer agent project config
    ├── writer.md.example       — Writer agent project config
    └── security.md.example     — Security agent project config
```

## Usage

### Root CLAUDE.md

Copy `CLAUDE.md.example` to `~/.claude/CLAUDE.md`. Edit with your:
- Hostname and IP
- Domain name
- NAS/backup target IP
- Username

Claude Code loads this file automatically for every session. It provides baseline
infrastructure context so agents don't need it re-explained each time.

### Project Configs

Copy the relevant `.md.example` to your agent's project directory:

```bash
cp claude-code/projects/sysadmin.md.example ~/.claude/projects/sysadmin/CLAUDE.md
cp claude-code/projects/research.md.example ~/.claude/projects/research/CLAUDE.md
# ...etc
```

Project configs load when Claude Code is invoked in that project directory. They define the agent's purpose, key tools, scope, and session-start procedures.

## File Hierarchy

Claude Code loads CLAUDE.md files from most general to most specific:

```
~/.claude/CLAUDE.md                          ← Root (always loaded)
~/.claude/projects/<project>/CLAUDE.md       ← Agent-specific (loaded for that agent)
~/repos/<repo>/CLAUDE.md                     ← Repo-specific (loaded when in that repo)
```

Each layer adds context. The root file has infrastructure facts. Project files have agent-specific instructions. Repo files have per-repo coding standards and conventions.

## How Agents Are Invoked

Each agent runs in its own Claude Code project directory:

```bash
# Start the sysadmin agent session
cd ~/.claude/projects/sysadmin
claude

# Or via the matrix-dispatcher (automated)
# matrix-dispatcher polls each agent's own Matrix room and routes messages to that agent's project dir
```

The [matrix-dispatcher](../docs/components/agent/matrix-dispatcher.md) polls each agent's Matrix room and injects messages into the agent's stdin stream, enabling async operation from any Matrix client.

## Agent Isolation

Each agent has its own:
- Project directory with `CLAUDE.md` — defines scope and tools
- scoped-mcp manifest — controls the exact MCP tools available
- NATS user credentials — separate JetStream subject namespaces
- Memory path — `~/.claude/memory/agents/<agent>/`

Agents share `~/.claude/memory/shared/` for cross-agent communication.
See [`docs/components/agent/scoped-mcp.md`](../docs/components/agent/scoped-mcp.md) for architecture details.
