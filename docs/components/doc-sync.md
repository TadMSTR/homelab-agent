# doc-sync

doc-sync is a local documentation cache for the claudebox agent stack. It fetches official documentation for services and tools from upstream sources, converts and chunks it into searchable markdown files, and stores them in the memsearch-indexed memory directory. Agents query the cache during task execution instead of fetching live URLs each time — eliminating network dependency and reducing token cost.

It sits in [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) alongside the memory pipeline, feeding into the same memsearch index that agents use for session recall.

## Why doc-sync

Agents frequently need reference material — SWAG nginx config syntax, Authentik forward auth setup, Compose file options, service-specific API docs. Without a local cache, every request either burns tokens on a web fetch, relies on the model's (potentially outdated) training knowledge, or blocks on network availability.

doc-sync solves this by pre-fetching and indexing the docs for every service in the stack. When an agent needs to configure SWAG for a new service, `memsearch search "SWAG authentik forward auth"` returns the relevant cached content in milliseconds — no web request, no hallucination risk from stale training data.

## How It Works

```
doc-sync.py (PM2 cron, 3 AM daily)
  │
  ├─ reads ~/docs/doc-sync.yml (service → topic → URL entries)
  │
  ├─ for each entry:
  │    ├─ fetch URL (prefer raw markdown; HTML → markdown via html2text)
  │    ├─ chunk at H2 headings (H3 fallback for oversized chunks)
  │    └─ write chunks to ~/.claude/memory/docs/<service>/
  │         (each chunk is a separate .md file with YAML frontmatter)
  │
  └─ runs memsearch index on ~/.claude/memory/docs/
       → immediately searchable via memsearch or archival-search
```

### Chunk Format

Each chunk is written as a standalone markdown file with frontmatter:

```yaml
---
type: doc-cache
tier: working
service: swag
topic: authentik-server-conf
section: Overview
source_url: https://raw.githubusercontent.com/...
created: 2026-04-01
expires: 2026-07-01
tags: [doc-cache, swag, docs]
---

<chunk content>
```

Agents can filter by `service` or `topic` tag in memsearch queries without needing embedding search — useful when you know the service but not the specific keyword.

### Cache Location

```
~/.claude/memory/docs/
├── swag/
│   ├── overview-00-overview.md
│   ├── authentik-server-conf-00-overview.md
│   └── authentik-location-conf-00-overview.md
├── authentik/
│   ├── nginx-forward-auth-00-...md
│   └── ...
├── grafana/
├── loki/
└── <42 services total>
```

## Configuration

The catalog lives at `~/docs/doc-sync.yml`:

```yaml
services:

  swag:
    - topic: overview
      url: https://raw.githubusercontent.com/linuxserver/docker-swag/master/README.md
    - topic: authentik-server-conf
      url: https://raw.githubusercontent.com/linuxserver/docker-swag/master/root/defaults/nginx/authentik-server.conf.sample

  authentik:
    - topic: nginx-forward-auth
      url: https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_nginx/
    - topic: forward-auth-overview
      url: https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth/
```

Prefer raw markdown sources (`raw.githubusercontent.com`, `llms.txt`, `.md` URLs) over HTML when available — they chunk more cleanly. For HTML pages, point at the most focused single page rather than a top-level docs index.

**Adding a new service:** add an entry to `doc-sync.yml` under the service name, then run manually or wait for the 3 AM cron.

## PM2 Service

`doc-sync-daily` runs at 3 AM daily:

```
script: /usr/bin/python3 $HOME/scripts/doc-sync.py
cron:   0 3 * * *
```

Logs to `~/docs/doc-sync.log`. A companion file, `~/docs/cache-manifest.md`, is rewritten after each run with a summary of what's cached (service, topic, chunk count, sync date).

State is tracked at `~/docs/doc-sync-state.json` — this is how doc-sync detects what changed between runs. The cache files themselves are the durable output; the state file is just bookkeeping.

## CLI Usage

```bash
# Sync all services
python3 ~/scripts/doc-sync.py

# Sync one service only
python3 ~/scripts/doc-sync.py --service swag

# Re-sync everything regardless of state
python3 ~/scripts/doc-sync.py --force

# Preview what would run without writing
python3 ~/scripts/doc-sync.py --dry-run
```

## How Agents Use It

Cached docs are in `~/.claude/memory/docs/`, indexed into memsearch by doc-sync after each sync run. Agents query them the same way they query any other memory:

```bash
# Direct memsearch query
memsearch search "SWAG authentik forward auth setup"

# Via archival-search skill (queries all tiers, including doc cache)
/archival-search "loki log shipping configuration"
```

The `type: doc-cache` frontmatter distinguishes these results from session memories and working notes in search output — they show up with a different tier label in archival-search results.

No special agent configuration is needed. Any agent that has access to memsearch (all of them) gets the doc cache for free.

## Prerequisites

```bash
pip install requests html2text pyyaml
```

Python 3.11+. No API keys, no GPU — doc-sync fetches from public URLs and runs entirely on CPU.

## Gotchas

**Chunk expiry is passive.** The `expires` frontmatter date is metadata for agents — doc-sync doesn't automatically delete expired files. Outdated chunks stay in the cache until the next sync for that topic rewrites them. If a service's docs change significantly between syncs, run `--force --service <name>` to refresh immediately.

**HTML quality varies.** Some documentation sites produce noisy markdown after html2text conversion — navigation menus, sidebars, and footer links end up in chunks. Prefer raw markdown URLs when available. If a service's cached chunks look noisy, switching its URL to a GitHub raw source usually fixes it.

**`--service` skips the memsearch index step.** Running `doc-sync.py --service <name>` syncs only that service and does not re-index — a partial index would leave other services' stale chunks untouched but also miss the updated chunks. After a targeted sync, run `memsearch index ~/.claude/memory/docs` manually to update the index.

## Related Docs

- [memsearch](memsearch.md) — the semantic search index that makes the cache queryable
- [memory-pipeline](memory-pipeline.md) — the broader nightly pipeline doc-sync runs alongside
- [Architecture overview](../../README.md#layer-3--multi-agent-claude-code-engine) — Layer 3 context
