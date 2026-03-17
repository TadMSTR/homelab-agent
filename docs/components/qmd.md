# qmd

qmd is a semantic search engine with an MCP server mode. It provides hybrid search — BM25 keyword matching, vector similarity, and optional LLM reranking — over your repos, docs, agent memory, and any other markdown or text collections you point it at. Local embeddings, no external API keys, GPU-accelerated if you have a compatible card.

It sits across [Layer 1](../../README.md#layer-1--host--core-tooling) and [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture. In Layer 1 it runs as a stdio MCP server for Claude Desktop. In Layer 2 it runs as an HTTP service (managed by PM2) that LibreChat and other clients can query.

## Why qmd

The memory system described in the [main README](../../README.md#the-memory--context-system) generates a lot of markdown — infrastructure docs, session summaries, agent memory files, distilled knowledge. That content is only useful if you can find the right piece at the right time. qmd makes it searchable.

Without it, you're relying on grep or hoping Claude remembers something from a CLAUDE.md file that happened to be loaded. With qmd, Claude can search semantically — "how did I configure the NFS mounts?" surfaces the relevant infrastructure doc even if the query doesn't match the exact wording. That's the difference between a context system and a pile of markdown files.

## How It Works

qmd indexes collections of documents into a local SQLite database with both full-text search (BM25) and vector embeddings. When you query it, it runs both retrieval methods in parallel and merges the results. Optionally, it can use an LLM to rerank the merged results for better precision.

The embedding model runs locally — qmd ships with GGUF model support and uses your CPU or GPU for inference. On an AMD iGPU (Radeon 780M) via Vulkan, embedding generation is about 3.5x faster than CPU-only. Nvidia GPUs work via CUDA. No GPU means it falls back to CPU, which is fine for small-to-medium collections.

**Index stats (this setup):** 322 files, 1554 embedded chunks, 17 collections — covering the prime-directive repo, agent memory, deploy scripts, compose files, Grafana dashboards, and MCP server repos.

## Dual Transport

qmd serves two different clients through two different transports:

| Transport | Client | How It Runs |
|-----------|--------|-------------|
| stdio | Claude Desktop | `qmd mcp` — launched by Claude Desktop as a subprocess |
| HTTP | LibreChat, other tools | `qmd mcp --http --port 8181` — PM2 managed, bound to `0.0.0.0` |

The stdio transport is standard MCP — Claude Desktop launches it, communicates via stdin/stdout, done. The HTTP transport runs as a long-lived PM2 service so that LibreChat (and anything else on the Docker network) can reach it at `http://host.docker.internal:8181` or the host IP.

For Claude Desktop config, see [`mcp-servers/README.md`](../../mcp-servers/README.md#qmd-semantic-search). For PM2 config, see [`pm2/ecosystem.config.js.example`](../../pm2/ecosystem.config.js.example).

## Prerequisites

- Node.js 22+ and npm
- `npm install -g @tobilu/qmd`
- Content to index (a context repo, agent memory directory, or any collection of markdown/text files)
- Optional: AMD GPU (Vulkan) or Nvidia GPU (CUDA) for faster embedding generation

## Configuration

qmd configuration lives in `~/.config/qmd/config.toml` (or wherever `QMD_CONFIG` points). Collections are defined here — each one points at a directory or git repo to index:

```toml
[[collections]]
name = "my-context-repo"
path = "~/repos/my-context-repo"

[[collections]]
name = "agent-memory"
path = "~/.claude/memory"

[[collections]]
name = "docker-compose"
path = "~/docker"
glob = "**/docker-compose.yml"
```

After defining collections, build the index with `qmd index`. This scans all configured paths, chunks the documents, generates embeddings, and stores everything in `~/.cache/qmd/index.sqlite`.

### Reindexing

The index doesn't auto-update when files change. This setup runs a PM2 cron job (`qmd-reindex`) at 5:00 AM daily that pulls the latest from all git repos and re-runs `qmd index`. If you're making frequent changes and need fresher results, run `qmd index` manually or increase the cron frequency.

### Collection Discovery

The index only covers repos explicitly listed in `~/.config/qmd/index.yml`. It won't automatically pick up new repos you clone. A second PM2 cron job (`qmd-repo-check`, runs at 9:00 AM daily) handles this by scanning the repos directory and comparing against the index config.

Repos matching configured keywords (`claude`, `claudebox`, `mcp` by default) are auto-added to `index.yml` and a reindex is triggered immediately. Everything else lands in a push notification for manual review. State is hashed on the unreviewed set, so you won't get re-notified daily for the same backlog — only when the set changes (new repo cloned, or you manually add one).

The script lives at [`scripts/check-qmd-repos.sh`](../../scripts/check-qmd-repos.sh). Keywords and the repos directory are configured at the top of the file.

### HTTP Bind Address

By default, qmd's HTTP mode binds to `localhost`, which means Docker containers can't reach it. To bind to all interfaces, set the `QMD_HOST` environment variable to `0.0.0.0` in your PM2 ecosystem config.

**Note:** The upstream `mcp/server.js` doesn't read `QMD_HOST` out of the box — there's a one-line sed patch required after installing or updating qmd:

```bash
sudo sed -i 's/httpServer.listen(port, "localhost"/httpServer.listen(port, process.env.QMD_HOST || "localhost"/' \
  /usr/lib/node_modules/@tobilu/qmd/dist/mcp/server.js
```

This patch needs to be reapplied after every `npm install -g @tobilu/qmd`. It's tracked as something to check in the dep-update PM2 job. After a major version upgrade, also run `qmd embed -f` to rebuild the vector index — the embedding format may have changed.

## Integration Points

**Claude Desktop:** Loads qmd as a stdio MCP server. Agents can search across all indexed collections during conversation. This is the primary way the memory system gets queried.

**LibreChat:** Connects to qmd's HTTP endpoint for RAG (retrieval-augmented generation). LibreChat sends search queries to `http://HOST:8181`, gets relevant chunks back, and includes them as context in the LLM prompt.

**memsearch:** Separate from qmd. memsearch handles Claude Code's auto-injected memory recall; qmd handles broader document search. They index overlapping content (both cover `~/.claude/memory/`) but serve different purposes and different clients.

**qmd-reindex cron:** PM2 cron job that keeps the index fresh. Pulls git repos, re-runs embedding generation.

**qmd-repo-check cron:** PM2 cron job that watches for new repos not yet in the QMD index. Auto-adds repos matching configured keywords; notifies for anything else. See [Collection Discovery](#collection-discovery) above.


## Gotchas and Lessons Learned

**GPU detection can be finicky.** qmd uses Vulkan for AMD GPUs, which requires the Vulkan SDK and appropriate drivers. If embedding generation is slower than expected, check `vulkaninfo` to confirm the GPU is detected. On a headless Debian box, you may need `mesa-vulkan-drivers` and `vulkan-tools` packages.

**Index size is manageable.** 157 docs / 823 chunks produces an index database of about 50MB. This is small enough that full re-indexing runs in under a minute on the AMD iGPU. You don't need to worry about incremental indexing at homelab scale.

**The `slim` vs `full` embedding model matters.** qmd supports different GGUF embedding models. The default is good for English-language content. If you're indexing code-heavy repos, consider a code-optimized embedding model — but for infrastructure docs and memory files, the default works well.

**SQLite locking.** If both the stdio and HTTP instances try to write to the index simultaneously (rare, but possible during reindexing), you'll get SQLite lock errors. The reindex cron runs at 5 AM when nobody's querying, which avoids this in practice.

## Standalone Value

qmd is useful well beyond this stack. If you have any collection of markdown documentation — a personal wiki, project docs, meeting notes — qmd gives you semantic search over it with zero cloud dependencies. Install it, point it at a directory, build an index, and search. The MCP integration with Claude Desktop is a bonus, but the CLI search is valuable on its own.

## Further Reading

- [qmd GitHub](https://github.com/tobi/qmd)
- [MCP Protocol documentation](https://modelcontextprotocol.io/)

---

## Related Docs

- [Architecture overview](../../README.md#architecture) — where qmd fits across Layers 1 and 2
- [MCP servers reference](../../mcp-servers/README.md#qmd-semantic-search) — config pattern and adoption guidance
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — qmd HTTP service and reindex cron definitions
- [LibreChat](librechat.md) — uses qmd's HTTP endpoint for RAG
- [memsearch](memsearch.md) — complementary memory search for Claude Code sessions
