# Hister

Hister is a browser-based semantic and keyword search UI over forge's knowledge corpus.
It indexes mounted document collections and provides a search interface at
`hister.helmforge.me`. When no results are found in indexed content, it redirects to
SearXNG for a web search fallback.

- **Image:** `ghcr.io/asciimoo/hister` (SHA-pinned)
- **URL:** `https://hister.helmforge.me`
- **Port:** `4433` (internal, SWAG-proxied)
- **Appdata:** `/opt/appdata/hister/`

## Indexed Collections

| Mount | Content |
|-------|---------|
| `/mnt/agent-platform-kb` | `~/repos/gitea/agent-platform` (read-only) |
| `/mnt/host-forge-kb` | `~/repos/gitea/host-forge` (read-only) |
| `/mnt/memory-shared` | `~/.claude/memory/shared/` (read-only) |

The agent-platform and host-forge KB repos are the primary reference material for forge
infrastructure. Memory shared notes give Hister visibility into working memory decisions.

## Search Fallback

`HISTER__APP__REDIRECT_ON_NO_RESULTS=true` — if a query matches nothing in the indexed
collections, the browser is redirected to `search.helmforge.me/search?q={query}` (SearXNG).
This makes Hister a unified entry point: local KB first, web search as a fallback.

## Hardening

```yaml
user: '1000:1000'
security_opt: [no-new-privileges:true]
read_only: true
tmpfs: /tmp
```

All mounted volumes are read-only. The container cannot write to any knowledge base source.

## Config

Hister config lives at `/opt/appdata/hister/config.yml`. Collection definitions (which
directories to index, display names) are set there.

## Related Docs

- [searxng.md](searxng.md) — the web search fallback target
- [memory-stack.md](memory-stack.md) — Milvus/OpenSearch backends (separate from Hister's own index)
