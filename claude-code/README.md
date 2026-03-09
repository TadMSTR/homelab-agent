# Claude Code Configuration

Templates and examples for setting up Claude Code with structured context and scoped memory. These files are meant to be adapted to your environment — replace placeholder values with your actual infrastructure details.

## Files

**[CLAUDE.md.example](CLAUDE.md.example)** — Root CLAUDE.md template. This file loads for every Claude Code session and provides baseline infrastructure context: host inventory, key paths, global rules. Keep it tight — under 60 lines. Detailed context goes in project-specific files.

**[projects/](projects/)** — Per-agent CLAUDE.md examples. Each file configures a domain-specific agent with its own tools, memory paths, and conventions:

| Agent | File | Domain |
|-------|------|--------|
| homelab-ops | [homelab-ops.md](projects/homelab-ops.md) | Infrastructure management, Docker, monitoring, backups |
| dev | [dev.md](projects/dev.md) | Code development, git workflows, repo conventions |
| research | [research.md](projects/research.md) | Technical research, findings format, knowledge capture |
| memory-sync | [memory-sync.md](projects/memory-sync.md) | Automated knowledge distillation from agent memory |

## How It Works

Claude Code loads CLAUDE.md files in order of specificity:

```
~/.claude/CLAUDE.md                          ← Root (always loaded)
~/.claude/projects/<project>/CLAUDE.md       ← Project-specific (loaded in that project)
~/repos/<repo>/CLAUDE.md                     ← Repo-specific (loaded in that repo)
```

Copy `CLAUDE.md.example` to `~/.claude/CLAUDE.md` and fill in your infrastructure details. Copy the project files you want to `~/.claude/projects/<name>/CLAUDE.md`.

## Related Docs

- [Main README — Layer 3](../README.md#layer-3--multi-agent-claude-code-engine) — Architecture context for the agent engine
- [memsearch](../docs/components/memsearch.md) — Memory recall that works alongside CLAUDE.md context
- [memory-sync](../docs/components/memory-sync.md) — Automated knowledge distillation pipeline
