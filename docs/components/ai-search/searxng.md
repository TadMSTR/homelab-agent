# SearXNG

SearXNG is forge's private meta-search engine. It aggregates results from multiple
search backends without storing queries or tracking users. Forge agents and Open WebUI
use it as the web search backend.

- **Image:** `searxng/searxng:latest`
- **URL:** `search.helmforge.me`
- **Port:** `127.0.0.1:8081` → container `8080`
- **Networks:** `forge-net` + `searxng-internal`

## Stack

| Container | Image | Purpose |
|-----------|-------|---------|
| `searxng` | `searxng/searxng:latest` | Meta-search frontend |
| `searxng-dragonfly` | `docker.dragonflydb.io/dragonflydb/dragonfly:v1.37.2` | Redis-compatible result cache |
| `searxng-hister` | see [hister.md](hister.md) | Memory search UI with SearXNG fallback |
| `searxng-mcp` | `searxng-mcp:local` | Web search + fetch cascade MCP — see [searxng-mcp.md](searxng-mcp.md) |

`searxng-dragonfly` is on `searxng-internal` (isolated) and `forge-net`. SearXNG
connects to it via `valkey://searxng-dragonfly:6379/0`. `searxng-hister` and `searxng-mcp`
joined this stack (`~/docker/searxng/docker-compose.yml`) in the 2026-08-23 consolidation.

## Hardening

```yaml
cap_drop: [ALL]
cap_add: [CHOWN, SETGID, SETUID]
tmpfs: /var/cache/searxng (64 MB)
```

Logs are capped at 1 MB / 1 file to minimize disk usage for a search service.

## Configuration

Settings at `/opt/appdata/searxng/searxng/settings.yml`. Enabled engines and categories
are managed there — SearXNG ships with many engines disabled by default.

## Agent Integration

SearXNG is registered as the search backend in Open WebUI and available to agents via
the `searxng-mcp` tool server — a container in this compose stack as of the 2026-08-23
consolidation, `127.0.0.1:8504`, bearer-authed. See [searxng-mcp.md](searxng-mcp.md) for
the MCP deployment. The `hister` memory search UI also integrates with SearXNG for
fallback web searches when no memory results are found.

## Related Docs

- [hister.md](hister.md) — memory search UI with SearXNG fallback
- [open-webui.md](open-webui.md) — uses SearXNG for web-augmented responses
