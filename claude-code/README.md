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
| security | [security.md](projects/security.md) | Post-build security audits, findings triage, action plan routing |

## How It Works

Claude Code loads CLAUDE.md files in order of specificity:

```
~/.claude/CLAUDE.md                          ← Root (always loaded)
~/.claude/projects/<project>/CLAUDE.md       ← Project-specific (loaded in that project)
~/repos/<repo>/CLAUDE.md                     ← Repo-specific (loaded in that repo)
```

Copy `CLAUDE.md.example` to `~/.claude/CLAUDE.md` and fill in your infrastructure details. Copy the project files you want to `~/.claude/projects/<name>/CLAUDE.md`.

## Skills

Claude Code supports a native skills system. Skills are `SKILL.md` files that Claude loads automatically when relevant or that you can invoke with `/skill-name`. They're the Claude Code equivalent of Claude Desktop's skills plugin.

Personal skills live at `~/.claude/skills/<skill-name>/SKILL.md` and are available across all projects. Project-scoped skills can also live in `.claude/skills/` within a repo.

If you're already managing a context repo for infrastructure docs, skills, and project instructions, the cleanest approach is to keep the source files there and symlink into `~/.claude/skills/`:

```bash
# Store the skill in your context repo
mkdir -p ~/repos/personal/YOUR_CONTEXT_REPO/skills/docker-stack-setup

# Symlink into ~/.claude/skills/
ln -s ~/repos/personal/YOUR_CONTEXT_REPO/skills/docker-stack-setup \
      ~/.claude/skills/docker-stack-setup
```

This keeps skills version-controlled alongside the rest of your context without maintaining a separate copy. Edits to the SKILL.md are immediately live — Claude Code does live reload on skill files.

The same symlink approach works for project instructions:

```bash
# ~/.claude/projects/<name>/ contains session data — symlink just the CLAUDE.md
ln -s ~/repos/personal/YOUR_CONTEXT_REPO/claude-projects/homelab-ops/CLAUDE.md \
      ~/.claude/projects/homelab-ops/CLAUDE.md
```

See [config-version-control](../docs/components/config-version-control.md) for how the context repo fits into the broader version control and backup strategy.

## Related Docs

- [Main README — Layer 3](../README.md#layer-3--multi-agent-claude-code-engine) — Architecture context for the agent engine
- [memsearch](../docs/components/memsearch.md) — Memory recall that works alongside CLAUDE.md context
- [memory-sync](../docs/components/memory-sync.md) — Automated knowledge distillation pipeline
