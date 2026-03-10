# Open Notebook

Open Notebook is an AI-powered research and document analysis tool. You upload documents (PDFs, articles, notes), and it provides AI-assisted analysis, summarization, and question-answering over your content. It uses a Streamlit web frontend and SurrealDB as its backend database.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture, accessible at `notebook.yourdomain` behind SWAG + Authelia.

## Why Open Notebook

Open Notebook fills a different niche than LibreChat. LibreChat is for general chat, agent interactions, and web research. Open Notebook is for working with your own documents — uploading a PDF, asking questions about it, building a research notebook around a topic.

It's the newest addition to the stack and the one I'm still evaluating. The document analysis capabilities are solid, and SurrealDB's GraphQL support makes it interesting for future integrations. Whether it stays long-term depends on how much I use it versus just feeding documents to LibreChat directly.

## What's in the Stack

Two containers:

| Container | Image | Purpose | RAM |
|-----------|-------|---------|-----|
| open-notebook | lfnovo/open_notebook:v1-latest | Streamlit UI + REST API | ~250MB |
| open-notebook-surrealdb | surrealdb/surrealdb:v2 | Document storage + GraphQL | ~150MB |

See [`docker/open-notebook/docker-compose.yml`](../../docker/open-notebook/docker-compose.yml) for the compose file.

## Prerequisites

- Docker CE + Compose
- An Anthropic or OpenAI API key (configured through the Open Notebook UI after first login)

## Configuration

### Environment Variables

Open Notebook requires two secrets in a `.env` file alongside the compose file:

```bash
# Encryption key for stored data
ENCRYPTION_KEY=YOUR_ENCRYPTION_KEY          # Generate with: openssl rand -hex 32

# SurrealDB root password — must match between both containers
SURREAL_PASSWORD=YOUR_SURREAL_PASSWORD      # Generate with: openssl rand -hex 32
```

The `SURREAL_PASSWORD` appears in both the SurrealDB service (via the `start` command) and the Open Notebook service (via `SURREAL_PASSWORD` env var). They must match.

### SurrealDB

SurrealDB runs with `SURREAL_EXPERIMENTAL_GRAPHQL=true` to enable GraphQL queries. It uses RocksDB for on-disk persistence, stored in `/opt/appdata/open-notebook/surrealdb/` on the host. The `user: root` directive in the compose file is required because SurrealDB needs write access to its data directory.

### Dual Port Proxy Configuration

Open Notebook exposes two ports: 8502 for the Streamlit web UI and 5055 for its REST API. If you're proxying through SWAG, the proxy conf needs to handle both. The Streamlit UI goes to the main location block, and the API gets its own location:

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name notebook.*;

    include /config/nginx/ssl.conf;
    include /config/nginx/authelia-server.conf;

    location / {
        include /config/nginx/authelia-location.conf;
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app open-notebook;
        set $upstream_port 8502;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;

        # WebSocket support for Streamlit
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
    }

    # REST API — used by the frontend for health checks and data ops
    location /config {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app open-notebook;
        set $upstream_port 5055;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;
    }
}
```

The `/config` location routes to the REST API on port 5055. The Streamlit frontend calls this internally for health checks and data operations. Without this second location block, the UI loads but can't communicate with its own backend.

## Gotchas and Lessons Learned

**Streamlit needs WebSocket headers.** Streamlit uses WebSockets for its reactive UI. If the SWAG proxy conf doesn't include the `Upgrade` and `Connection` headers, the UI partially loads but widgets don't respond and the page shows connection errors.

**SurrealDB experimental GraphQL flag.** The `SURREAL_EXPERIMENTAL_GRAPHQL=true` environment variable is required. Without it, Open Notebook's GraphQL queries fail and the app errors on startup. This is an experimental SurrealDB feature — check SurrealDB release notes before upgrading, as the API surface may change.

**Generate secrets before first start.** Both `ENCRYPTION_KEY` and `SURREAL_PASSWORD` must be set before the first `docker compose up`. SurrealDB creates its initial database with the root password on first start — changing it later requires wiping the data directory.

**The v1-latest tag.** Open Notebook uses `v1-latest` as its image tag, which tracks the latest v1.x release. This is fine for a homelab but means updates can arrive unexpectedly. If stability matters, pin to a specific version from the [releases page](https://github.com/lfnovo/open_notebook/releases).

## Standalone Value

Open Notebook is fully independent — it doesn't require any other component from this stack. It's a self-contained document analysis tool that works with a bare `docker compose up -d` and an LLM API key. If you want AI-powered document analysis and don't need the full homelab-agent platform, this is a clean standalone deployment.

## Further Reading

- [Open Notebook GitHub](https://github.com/lfnovo/open_notebook)
- [SurrealDB documentation](https://surrealdb.com/docs)
- [Streamlit documentation](https://docs.streamlit.io/)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where Open Notebook fits in the three-layer stack
- [SWAG](swag.md) — reverse proxy and SSL for `notebook.yourdomain`
- [Authelia](authelia.md) — SSO protecting the Open Notebook UI
- [Docker compose file](../../docker/open-notebook/) — Open Notebook stack compose
