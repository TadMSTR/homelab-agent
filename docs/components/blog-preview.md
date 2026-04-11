# blog-preview

blog-preview is a local MkDocs Material server for drafting and previewing blog articles before publishing. It serves the `~/repos/personal/blog/` repository at `blog-preview.<your-claudebox-domain>`, giving a rendered view of articles with live reload as files change.

It sits in [Layer 1](../../README.md#layer-1--docker-infrastructure) of the architecture — a lightweight Docker container with no agent integration, used directly by Ted during writing sessions.

## Why blog-preview

Blog articles are written in markdown and published externally (dev.to via the `publish-devto` skill). Writing in a plain text editor gives no sense of how the rendered article looks — headings, code blocks, admonitions, and table of contents all behave differently in a rendered view than in raw markdown. blog-preview provides that rendered view locally before anything gets published.

## How It Works

The stack is a single `squidfunk/mkdocs-material` container mounted against the blog repo:

- **Port:** `127.0.0.1:8082` → container port 8000
- **Volume:** `$HOME/repos/personal/blog:/docs`
- **Network:** `claudebox-net` (reached by SWAG)
- **SWAG proxy:** `blog-preview.<your-claudebox-domain>` with Authelia forward auth

MkDocs Material serves the `articles/` directory (set via `docs_dir: articles` in `mkdocs.yml`) with live reload. Edits to any `.md` file under `articles/` are reflected in the browser within a second or two.

## Configuration

`mkdocs.yml` in the blog repo root:

```yaml
site_name: Blog Drafts
docs_dir: articles
theme:
  name: material
  palette:
    scheme: slate
    primary: indigo
  features:
    - navigation.instant
    - content.code.copy

use_directory_urls: false

plugins:
  - search

markdown_extensions:
  - toc:
      permalink: true
  - admonition
  - pymdownx.highlight
  - pymdownx.superfences
```

`use_directory_urls: false` keeps article URLs flat (`/article-name.html` rather than `/article-name/`) — matches how dev.to renders published articles.

## Stack

```
~/docker/blog-preview/docker-compose.yml
```

```yaml
services:
  blog-preview:
    image: squidfunk/mkdocs-material
    container_name: blog-preview
    volumes:
      - $HOME/repos/personal/blog:/docs
    ports:
      - "127.0.0.1:8082:8000"
    restart: unless-stopped
    networks:
      - claudebox-net
```

## Repo Layout

```
~/repos/personal/blog/
├── mkdocs.yml
└── articles/
    ├── index.md
    └── <article-name>.md   # one file per article
```

Articles are standalone markdown files. The index.md provides a landing page / table of contents when browsing the preview site.

## Integration Points

**publish-devto skill:** The primary publishing path. The writer agent drafts articles in `articles/`, the blog-preview container renders them locally for review, and the `publish-devto` skill submits the final markdown to the dev.to API.

**SWAG + Authelia:** `blog-preview.<your-claudebox-domain>` is proxied through the claudebox SWAG instance with Authelia forward auth — accessible over HTTPS from any device on the LAN without exposing the port directly.

**repo-sync-nightly:** The blog repo is included in the nightly repo-sync job (PM2 ID 24) — auto-committed and pushed at 23:30 daily. See [repo-sync-nightly](repo-sync-nightly.md).

## Gotchas and Lessons Learned

**Container doesn't hot-reload on first start.** MkDocs Material's dev server starts in watch mode by default, but if the container starts before the blog repo is populated (e.g. after a fresh clone), it may serve a blank index. Restart the container after the repo is in place.

**`use_directory_urls: false` matters for dev.to parity.** With directory URLs enabled, MkDocs renders `/article-name/index.html` — links and anchors inside articles behave differently than on dev.to's flat URL structure. Keep it disabled.

**No build step.** This is a live dev server, not a static site generator. The container uses `mkdocs serve`, not `mkdocs build` — there's no `site/` output directory to deploy. Publishing goes through dev.to directly, not from MkDocs output.

## Related Docs

- [publish-devto skill](../../claude-code/skills/publish-devto/) — publishes articles to dev.to via the Forem API
- [repo-sync-nightly](repo-sync-nightly.md) — nightly auto-commit and push for the blog repo
- [SWAG](swag.md) — reverse proxy and Authelia integration
