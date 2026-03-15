# Architecture

This document expands on the architecture overview in the [main README](../README.md#architecture) with detail on data flows, network topology, and how the three layers interconnect. Read the README first — this doc assumes you're familiar with the layer model and component list.

## System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 3: Multi-Agent Claude Code Engine                             │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐           │
│  │homelab-  │  │  dev     │  │ research │  │ memory-sync │           │
│  │  ops     │  │          │  │          │  │  (PM2 cron) │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬──────┘           │
│       │             │             │               │                  │
│       └─────────────┴──────┬──────┘               │                  │
│                            ▼                      ▼                  │
│                    ┌────────────────┐     ┌──────────────────┐       │
│                    │   memsearch    │     │  context repo    │       │
│                    │ (auto-recall)  │     │ (distilled notes)│       │
│                    └────────────────┘     └──────────────────┘       │
├──────────────────────────────────────────────────────────────────────┤
│  Layer 2: Self-Hosted Service Stack (Docker)                         │
│                                                                      │
│  ┌──────┐  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌─────────┐    │
│  │ SWAG │──│ Authelia │  │ LibreChat │  │ SearXNG  │  │Dockhand │    │
│  │(proxy)│ │  (SSO)   │  │           │  │+ SearXNG │  │         │    │
│  └──┬───┘  └──────────┘  └─────┬─────┘  └──────────┘  └─────────┘    │
│     │                          │                                     │
│     │    ┌──────┐              │    ┌─────────────┐                  │
│     │    │ qmd  │──────────────┘    │Open Notebook│                  │
│     │    │(HTTP)│                   └─────────────┘                  │
│     │    └──────┘                                                    │
├──────────────────────────────────────────────────────────────────────┤
│  Layer 1: Host & Core Tooling                                        │
│                                                                      │
│  ┌────────────────┐  ┌──────────────────────────────────────┐        │
│  │ Claude Desktop │──│ MCP Servers                          │        │
│  │                │  │ Netdata·Grafana·GitHub·DC·Playwright │        │
│  │                │  │ basic-memory·qmd(stdio)·InfluxDB     │        │
│  │                │  │ Unraid·TrueNAS·Bluesky               │        │
│  └────────────────┘  └──────────────────────────────────────┘        │
│                                                                      │
│  ┌────────────┐  ┌─────────────┐                                     │
│  │ Guacamole  │  │  PM2        │                                     │
│  │(remote GUI)│  │(svc manager)│                                     │
│  └────────────┘  └─────────────┘                                     │
└──────────────────────────────────────────────────────────────────────┘
```

## Network Topology

Everything runs on a single host. Docker containers share one bridge network (`claudebox-net` in this setup — name yours whatever you want). Host-level services (qmd, CUI, PM2 jobs) communicate with Docker containers via the bridge network or `host.docker.internal`.

```
Internet ──✕── (no inbound ports exposed)

DNS: *.yourdomain → host LAN IP (Cloudflare DNS, internal only)

Host network:
  ├── Claude Desktop (GUI)
  ├── Guacamole (port 8080, or proxied)
  ├── qmd HTTP (port 8181, bound 0.0.0.0)
  ├── CUI (port 3001)
  └── PM2 services (no ports, cron jobs)

Docker bridge network (claudebox-net):
  ├── swag (443 → host, routes *.yourdomain)
  │     ├── → authelia:9091  (SSO checks)
  │     ├── → librechat:3080
  │     ├── → dockhand:3000
  │     ├── → open-notebook:8502
  │     └── → cui:3001 (host service, via host.docker.internal)
  ├── authelia
  ├── librechat + mongodb + meilisearch
  │     └── → host:8181 (qmd HTTP, for RAG)
  ├── searxng + valkey
  │     └── searxng serves librechat web search queries
  ├── dockhand (+ Docker socket mount)
  └── open-notebook + surrealdb
```

No ports are exposed to the internet. SWAG handles SSL via DNS validation (Cloudflare API), not HTTP challenge. The domain resolves to a LAN IP — it's internal-only access with real SSL certificates.

## Data Flows

### Request Flow (User → Service)

When someone accesses `chat.yourdomain` in a browser:

1. DNS resolves to the host's LAN IP (Cloudflare DNS record, local network only)
2. SWAG receives the HTTPS request on port 443
3. SWAG checks Authelia for authentication (via `auth_request` in the nginx proxy conf)
4. Authelia validates the session cookie or redirects to the login page
5. On success, SWAG proxies to the target container (e.g., `librechat:3080`)

This flow is identical for every service behind SWAG. Adding a new service means: deploy the container on `claudebox-net`, add a SWAG proxy conf, uncomment the Authelia lines. Two minutes of work.

### Memory Flow (Knowledge Accumulation)

This is the core data flow that makes the system self-improving. Memory is organized into three tiers:

```
Claude Code session
  │
  ├── memsearch Stop hook auto-captures session summary
  │   └── SESSION TIER: .memsearch/memory/YYYY-MM-DD.md (per-project, 30-day retention)
  │         │
  │         └── memsearch indexes it (available for auto-recall in next session)
  │
  ├── Agent writes working notes during sessions
  │   └── WORKING TIER: ~/.claude/memory/shared/ or agents/<name>/ (90-day expiry)
  │         │
  │         └── YAML frontmatter: tier, created, source, expires, tags
  │
  └── memory-sync consolidation pipeline (4 AM daily, 8 steps)
        │
        ├── 1. Scan session notes (last 7 days, all project stores)
        ├── 2. Promote durable items → working tier
        ├── 3. Import LibreChat memory (optional)
        ├── 4. Review working notes >14 days old
        ├── 5. Promote qualifying notes → DISTILLED TIER
        │      └── context repo/memory/distilled/ (permanent, git-backed)
        ├── 6. Expire stale working notes (past 90 days)
        ├── 7. Dedup check (merge topical duplicates)
        └── 8. Log metrics + health report
              │
              └── qmd reindex (5 AM daily)
                    │
                    └── Distilled knowledge searchable by all agents
```

The three pipeline tiers serve different purposes: **session** is raw auto-captured context for immediate recall, **working** is agent-curated knowledge with a 90-day TTL, and **distilled** is permanent knowledge that passed the "would this matter in 3 months?" test. Notes flow upward through tiers — never skipping one — and each promotion is checked for duplicates.

A fourth layer sits outside the pipeline: **core context** (`~/.claude/memory/core-context.md`). This is a permanent, manually-managed file containing user profile, active projects, key constraints, and recent decisions. Unlike the other tiers, it is not written by memory-sync — it is updated via the `core-memory-update` skill and injected at every session start via a `SessionStart` hook (`inject-core-context.sh`) before any tool calls run. The 40-line cap keeps it under ~2KB so it never crowds out working memory injection.

The timing is deliberate: memory-sync at 4 AM, qmd-reindex at 5 AM, docker-stack-backup at 1 AM. Each depends on the previous one completing. PM2 cron handles the scheduling.

### Build Plan Handoff (Research → Implementation)

Research agents investigate, compare, and design — but don't execute infrastructure changes. When research produces an actionable plan:

1. The research agent writes a structured plan to a known directory
2. The plan includes a `handoff.md` with the target agent chat, status, and key decisions already made
3. The implementing agent checks for pending plans on session start
4. Status transitions: `pending` → `in-progress` → `complete`

This separation keeps research exploratory (no risk of accidental changes) and gives implementing agents a reviewed, pre-validated starting point. The handoff file is deliberately minimal — just enough context to start, with a path to the full plan for depth.

### Search Flow (qmd Dual Transport)

qmd serves two clients through different transports:

```
Claude Desktop ──stdio──→ qmd CLI process
                            │
                            └── queries ~/.cache/qmd/index.sqlite

LibreChat ──HTTP──→ qmd PM2 service (port 8181)
                      │
                      └── same index.sqlite
```

Both transports query the same index. The stdio instance is ephemeral (launched per-session by Claude Desktop). The HTTP instance is persistent (PM2 managed, always-on). They don't conflict because SQLite handles concurrent reads gracefully — writes only happen during reindexing, which runs at a different time.

## Storage Architecture

The host uses local NVMe for the OS, Docker, and all active workloads. NFS mounts from a storage server provide bulk storage and backup targets. The storage server is optional — everything runs fine without NFS, you just lose off-host backups and shared state.

```
Host (NVMe):
  /opt/appdata/<stack>/     ← Docker persistent data
  ~/.cache/qmd/             ← qmd search index
  ~/.memsearch/             ← memsearch vector DB
  ~/.claude/memory/         ← Agent memory files
  ~/repos/                  ← Git repositories
  ~/docker/                 ← Docker compose files (version controlled)

NFS (optional, from storage server):
  /mnt/storage/host-backup/ ← Backup target for docker-stack-backup
```

The `~/docker/` directory is a git repo. This is critical — AI agents (via Claude Desktop, Claude Code, or LibreChat) have filesystem access and will edit compose files, `.env` files, and proxy confs directly. Version control means every change is tracked, diffable, and reversible. If an agent makes a bad edit that breaks a stack, `git diff` shows exactly what changed and `git checkout` recovers it. Treat this the same way you'd treat infrastructure-as-code in a production environment.

The docker-stack-backup PM2 job rsyncs `/opt/appdata/` to the NFS mount nightly. If the NFS mount is unavailable, the backup job fails gracefully and the resource-monitor alerts via push notification.

## Security Model

This is a homelab, not an enterprise. The security model reflects that — good enough for a household, not trying to pass an audit.

**External access:** None. No ports are exposed to the internet. The domain is DNS-only (Cloudflare manages the DNS records, but traffic never routes through Cloudflare). Access is LAN-only, or via VPN/Guacamole if you need remote access.

**Authentication:** Authelia provides SSO for all web services. File-based user backend — no LDAP, no database, just a YAML file with bcrypt-hashed passwords. One-factor auth. This is appropriate for a single-user or small household setup. If you need multi-factor or a proper identity provider, Authelia supports both — but it's overkill for most homelabs.

**API keys and secrets:** Stored in `.env` files alongside Docker compose files, and in the Claude Desktop config for MCP servers. Not checked into git (the public repo uses placeholder values). In a more paranoid setup, you'd use a secrets manager — but for a homelab, `.env` files with restrictive permissions are fine.

**Docker socket access:** Dockhand mounts the Docker socket read-only for container management. This is a known risk surface — any container with socket access can potentially control other containers. Dockhand runs behind Authelia, so unauthorized access requires bypassing SSO first.

**MCP server access:** MCP servers that access external services (Unraid, TrueNAS, InfluxDB) use API keys with minimal permissions. The Unraid key is viewer-only (read access). The TrueNAS and InfluxDB keys are limited to their respective APIs. No MCP server has write access to anything it shouldn't.

## Scaling Considerations

This architecture is designed for a single host. If you need to scale:

**Multiple hosts for Docker services:** Move individual stacks to separate hosts. SWAG can proxy to remote hosts — just change the upstream from a container name to an IP address. Authelia stays on the SWAG host.

**Separate machine for Claude Code agents:** The Layer 3 agent engine (CLAUDE.md hierarchy, memsearch, PM2 jobs) can run on a different machine than the Docker services. qmd's HTTP transport handles this naturally — point LibreChat at the remote qmd host instead of localhost.

**Multiple Claude Desktop instances:** MCP servers are per-instance. If you run Claude Desktop on multiple machines, each needs its own MCP config. Shared state (memory files, context repo) should live on a network-accessible filesystem.

In practice, a single mini PC handles everything described in this repo without breaking a sweat. Scaling is a future problem.

---

## Related Docs

- [Main README](../README.md) — architecture overview and component list
- [Architecture decisions](decisions.md) — rationale behind major choices
- [Getting started](getting-started.md) — setup order and stopping points
- [MCP servers reference](../mcp-servers/README.md) — Layer 1 tool integrations
- [Component docs](components/) — per-service deep dives
- [PM2 ecosystem config](../pm2/ecosystem.config.js.example) — service scheduling and dependencies
