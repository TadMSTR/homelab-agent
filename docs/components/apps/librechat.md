# LibreChat

LibreChat is a self-hosted, multi-provider AI chat web application — one of the ways
forge agents and Ted's Claude subscription are surfaced as a conversational frontend
(Claude Gateway uses LibreChat as a frontend with session continuity for Claude
subscribers). It is a separate concern from the `librechat-mcp` sidecar, which gives
forge agents programmatic CRUD access to LibreChat's *own* agent definitions — this doc
covers the app stack itself.

- **URL:** `https://librechat.helmforge.me`
- **Stack:** `~/docker/librechat/`
- **Appdata:** `/opt/appdata/librechat/`

## Stack

| Container | Purpose |
|-----------|---------|
| `librechat` | Main application — chat UI, conversation state, provider routing |
| `librechat-mongodb` | Primary datastore — users, conversations, messages, presets |
| `librechat-meilisearch` | Full-text search index over conversation history |
| `librechat-mcp` | Sidecar MCP server for agent-driven LibreChat agent management — see [librechat-mcp.md](../mcp-servers/librechat-mcp.md) |

All four containers share the `librechat-internal` Docker network. Only `librechat`
itself is reachable externally, via SWAG.

## Port / Endpoint

- Public: `librechat.helmforge.me` (SWAG-proxied, Authentik forward auth)
- Internal: `librechat:3080` — the address `librechat-mcp` and other in-network sidecars
  use to reach the app directly

## Configuration

Stack-level `.env` (`~/docker/librechat/.env`, not committed — see `.env.example`)
holds provider API keys, session secrets, and the admin account credentials that
`librechat-mcp` authenticates with (`LIBRECHAT_MCP_EMAIL` / `LIBRECHAT_MCP_PASSWORD`).

MongoDB and Meilisearch use their own data volumes under `/opt/appdata/librechat/` and
are not exposed outside the `librechat-internal` network.

## Dependencies

- **Depends on:** `librechat-mongodb` (conversation/user data), `librechat-meilisearch`
  (search indexing) — both must be healthy before `librechat` will fully start
- **Depended on by:** `librechat-mcp` (`depends_on: librechat`, needs the app's
  `/api/auth/login` endpoint for JWT auth)

## Operations

```bash
# Status / logs
docker compose -f ~/docker/librechat/docker-compose.yml ps
docker logs librechat --tail 50
docker logs librechat-mongodb --tail 50
docker logs librechat-meilisearch --tail 50

# Restart the whole stack
cd ~/docker/librechat && docker compose restart

# Restart just the app (leaves mongo/meilisearch data untouched)
docker compose -f ~/docker/librechat/docker-compose.yml restart librechat
```

## scoped-mcp Integration

None directly — LibreChat is a user-facing app, not an MCP server. Agent access to
LibreChat's internals goes through the `librechat-mcp` sidecar, which is not yet wired
into any agent manifest (see [librechat-mcp.md](../mcp-servers/librechat-mcp.md)).

## Related Docs

- [librechat-mcp.md](../mcp-servers/librechat-mcp.md) — sidecar MCP server for agent-driven LibreChat agent CRUD
