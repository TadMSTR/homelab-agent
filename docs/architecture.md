# Architecture

This document expands on the architecture overview in the [main README](../README.md#architecture) with detail on data flows, network topology, and how the three layers interconnect. Read the README first — this doc assumes you're familiar with the layer model and component list.

## System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 3: Multi-Agent Claude Code Engine                             │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐         │
│  │homelab-  │  │  dev     │  │ research │  │ memory-sync │         │
│  │  ops     │  │          │  │          │  │  (PM2 cron) │         │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬──────┘         │
│       │              │              │               │                │
│       └──────────────┴──────┬───────┘               │                │
│                             ▼                       ▼                │
│                    ┌────────────────┐     ┌──────────────────┐       │
│                    │   memsearch    │     │  context repo    │       │
│                    │ (auto-recall)  │     │ (distilled notes)│       │
│                    └────────────────┘     └──────────────────┘       │
├──────────────────────────────────────────────────────────────────────┤
│  Layer 2: Self-Hosted Service Stack (Docker)                         │
│                                                                      │
│  ┌──────┐  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌─────────┐  │
│  │ SWAG │──│ Authelia  │  │ LibreChat │  │Perplexica│  │Dockhand │  │
│  │(proxy)│  │  (SSO)   │  │           │  │+ SearXNG │  │         │  │
│  └──┬───┘  └──────────┘  └─────┬─────┘  └──────────┘  └─────────┘  │
│     │                          │                                     │
│     │    ┌─────┐               │    ┌─────────────┐                  │
│     │    │ qmd │───────────────┘    │Open Notebook│                  │
│     │    │(HTTP)│                    └─────────────┘                  │
│     │    └─────┘                                                     │
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
  │     ├── → perplexica:3000
  │     ├── → dockhand:3000
  │     ├── → open-notebook:8502
  │     └── → cui:3001 (host service, via host.docker.internal)
  ├── authelia
  ├── librechat + mongodb + meilisearch
  │     └── → host:8181 (qmd HTTP, for RAG)
  ├── perplexica + searxng + valkey
  │     └── searxng also serves librechat search queries
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

This is the core data flow that makes the system self-improving:

```
Claude Code session
  │
  ├── Agent writes session summary → ~/.claude/memory/agents/<name>/
  │                                     │
  │                                     ├── memsearch indexes it
  │                                     │   (available for auto-recall in next session)
  │                                     │
  │                                     └── memory-sync reads it (4 AM daily)
  │                                           │
  │                                           ├── Filters for durable knowledge
  │                                           ├── Writes distilled notes → context repo
  │                                           └── Git commit + push
  │                                                 │
  │                                                 └── qmd reindex (5 AM daily)
  │                                                       │
  │                                                       └── Searchable by all agents
  │
  └── Claude Desktop / LibreChat conversations
        │
        └── (Optional) memory export → chat-staging/
              │
              └── memory-sync reads this too
```

The timing is deliberate: memory-sync at 4 AM, qmd-reindex at 5 AM, docker-stack-backup at 1 AM. Each depends on the previous one completing. PM2 cron handles the scheduling.

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
  ~/docker/                 ← Docker compose files

NFS (optional, from storage server):
  /mnt/storage/host-backup/ ← Backup target for docker-stack-backup
```

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
- [Getting started](getting-started.md) — setup order and stopping points
- [MCP servers reference](../mcp-servers/README.md) — Layer 1 tool integrations
- [Component docs](components/) — per-service deep dives
- [PM2 ecosystem config](../pm2/ecosystem.config.js.example) — service scheduling and dependencies
