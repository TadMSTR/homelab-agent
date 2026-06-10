# Forge Phase 2 — KB Seeding

**Completed:** 2026-05-12
**Commits:** `agent-platform/knowledge-base` @ `5bf51f5`, `host-forge/knowledge-base` @ `1963084`

## What Was Built

Initial knowledge base content committed to two atlas Gitea repos, curated from `ted/prime-directive`. Both repos now carry seed documents appropriate for their scope plus an `EXCLUDED.md` documenting what was intentionally not migrated. This establishes the content foundation that forge agent stacks mount read-only at runtime.

No services were deployed; this phase is documentation-only.

## KB Repos and Runtime Paths

| Repo | Runtime mount path | Purpose |
|------|--------------------|---------|
| `agent-platform/knowledge-base` | `/kb/platform/` | Platform-wide, host-agnostic KB |
| `host-forge/knowledge-base` | `/kb/forge/` | Forge operating environment KB |

Agent stacks that need both mount both checkouts. Phase 5 agent stacks mount both repos read-only.

## agent-platform/knowledge-base — Seeded Documents

| File | Content |
|------|---------|
| `platform-overview.md` | What the platform is: multi-user agent infrastructure on forge, BYO-subscription model, v0 scope |
| `agent-model.md` | Agent types and distinction: gateway agents vs resident agents, per-user stack model, how Claude Code authenticates |
| `communications.md` | How agents communicate: NATS/agent-bus, scoped-mcp tool surface, Matrix integration (future) |
| `onboarding.md` | How a new platform user is provisioned: Authentik identity, Gitea repo, user stack, Claude token submission via gateway auth UI |
| `EXCLUDED.md` | What was intentionally not migrated from `ted/prime-directive`: claudebox-specific paths, personal preferences, draft work, build history |

## host-forge/knowledge-base — Seeded Documents

| File | Content |
|------|---------|
| `hardware.md` | Forge host specs, GPU (NVIDIA 550.163.01), Ollama models (qwen3:14b, qwen3:4b, nomic-embed-text), storage |
| `network.md` | Network position, SWAG domains (`helmforge.me`), internal topology, Authentik-gated services |
| `services.md` | Running stacks on forge with ports and stack names — snapshot as of 2026-05-12; **update as stacks are deployed in future phases** |
| `paths.md` | Canonical directory layout: `~/docker/<stack>/`, `/opt/appdata/<stack>/`, per-user paths at `/opt/appdata/users/<user>/` |
| `users.md` | User model: operator (Ted, Linux user), platform users (Authentik-only, no shell), identity distinction |
| `backup.md` | Forge backup procedures, stack backup script, per-user stack backup extension (Phase 5) |
| `EXCLUDED.md` | What was intentionally not migrated: claudebox config, personal preferences, draft/in-progress docs |

## What Was Not Seeded

`agent-platform/agents` and `agent-platform/skills` are intentionally empty at Phase 2. They are seeded during Phase 5 (first user stack) when agent definitions and skills are finalised. Committing placeholder content now would require a replacement commit in Phase 5.

## Notes

- `services.md` in `host-forge/knowledge-base` reflects running stacks as of 2026-05-12. Update it when new stacks are deployed in subsequent phases — it is not auto-generated.
- `EXCLUDED.md` in each repo is the intentional record of non-migrated content. Do not remove it during future content additions; it prevents the excluded items from drifting back in.
- No security audit for this phase (documentation-only build; no credential changes, no services deployed, no forge shell commands).

## Next Phase

**Phase 3 — Claude Code on Forge:** Install Claude Code on forge host, authenticate, validate headless `claude -p`, validate reachability to forge Ollama and Authentik. Set up `~/.claude/projects/<project>/CLAUDE.md` for forge work.
