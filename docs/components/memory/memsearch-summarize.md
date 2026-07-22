# memsearch-summarize

Session transcript summarizer that polls memsearch spool directories, calls a configured LLM
provider (Anthropic, or a local Ollama/OpenAI-compatible endpoint) to generate bullet-point
summaries, and replaces raw transcripts in memory files. Also exposes a FastMCP MCP server
for on-demand summarization.

## Service

| Field | Value |
|-------|-------|
| PM2 name | `memsearch-summarize` |
| Type | always-on |
| Port | 8494 |
| Bind | 127.0.0.1 |
| Transport | streamable-http |
| Interpreter | `/opt/venvs/memsearch/bin/python3` (via launcher) |
| Script | `~/repos/gitea/host-forge-scripts/scripts/memsearch-summarize.py` |
| Launcher | `~/repos/gitea/host-forge-scripts/scripts/run-memsearch-summarize.py` |

The launcher reads `ANTHROPIC_API_KEY` from `~/.secrets/forge.env` and execs the main script
under the memsearch venv interpreter.

## How It Works

1. Polls `~/.memsearch/spool/` and all `~/.claude/projects/*/.memsearch/spool/` directories every 10 seconds
2. Each spool entry is a JSON file pointing to a memory file and a transcript block
3. Calls the configured LLM provider (`plugins.claude-code.summarize.provider` in
   `~/.memsearch/config.toml`) to summarize the transcript into 3–6 bullet points. Supports
   `anthropic` (hits `https://api.anthropic.com/v1/messages` directly, hardcoded URL) or any
   named OpenAI-compatible provider under `[llm.providers.<name>]` (e.g. Ollama). **Live
   config as of 2026-07-13: `provider = "ollama"`, `model = "summarize"`** (resolves to the
   Ollama tag `summarize:latest` via ollama-queue-proxy, `http://127.0.0.1:11435/v1`).
4. Replaces the raw transcript in the memory file with the summary
5. Marks the spool entry as `ok` (success), `retry` (transient failure), or `error` (permanent failure)

Rate limit handling: on HTTP 429, backs off to 3× the poll interval before retrying.

## Anti-Regurgitation

Mid-session skill/template dumps (e.g. a skill's `<name>`, `<specific step>` placeholder
text) used to leak into `.memsearch/memory/*.md` and get "summarized" verbatim instead of
described. Fixed in two layers:

- **Root cause (upstream):** `parse-transcript.sh` in the memsearch plugin (forge fork,
  `zilliztech/memsearch` PR #1) now skips `isMeta` turns in `format_turn()`, so skill/template
  content never reaches a memory file or the summarizer at all.
- **Defense-in-depth (this service):** `detect_contamination()` rejects a summary that
  contains an unresolved `<...>` placeholder token, a known template/skill signature (e.g. a
  `### Phase N` heading), or ≥3 consecutive lines copied verbatim from the raw transcript.
  On rejection it retries once with a stronger anti-copy reminder appended to the prompt; if
  the retry also trips the filter, it falls back to `build_fallback_note()` — a minimal
  deterministic note (first user line, re-checked against the same filter and dropped if it
  also trips, plus a suppression marker) instead of the model's output. The `summarize:latest`
  Ollama model also carries an anti-copy `SYSTEM` directive.

Rejections emit a `memsearch.summarize_rejected` OTel span (signal + attempt number) for
visibility in SigNoz. Expected to rarely trigger once the upstream `isMeta` fix is live —
it's a backstop, not the primary defense.

## MCP Tools

| Tool | Description |
|------|-------------|
| `spool_status` | Returns counts of pending/ok/retry/error entries across all spool dirs |
| `summarize_pending` | Triggers immediate summarization of all pending spool entries |
| `summarize_turn` | Summarizes a specific session turn by session ID and timestamp |

Not exposed through scoped-mcp agent manifests — runs as a standalone service.
Agents access summarized content through memsearch-mcp (8493) or qmd (8181) after
the summaries have been written back to memory files.

## Configuration

Config values from `~/.memsearch/config.toml`:

| Key | Default | Purpose |
|-----|---------|---------|
| `plugins.claude-code.summarize.provider` | `anthropic` | Selects `anthropic` or a named `[llm.providers.<name>]` OpenAI-compatible provider (e.g. `ollama`). **Live value: `ollama`.** |
| `plugins.claude-code.summarize.model` | `claude-sonnet-4-6` | LLM model for summarization. **Live value: `summarize`** (Ollama tag `summarize:latest`, qwen3:14b + `/no_think` template) |
| `plugins.claude-code.summarize.enabled` | `true` | Enable/disable summarization |
| `llm.providers.ollama.base_url` | — | OpenAI-compatible endpoint base URL, only read when provider ≠ `anthropic`. Live: `http://127.0.0.1:11435/v1` (ollama-queue-proxy) |
| `llm.providers.ollama.api_key` | — | Auth token for the OpenAI-compatible endpoint; only read when provider ≠ `anthropic` |
| `prompts.summarize` | built-in | Path to custom prompt file. Live: `~/.memsearch/prompts/summarize-local.txt` |

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `ANTHROPIC_API_KEY` | conditional — only when `plugins.claude-code.summarize.provider = "anthropic"` | — | API access (injected by launcher from forge.env) |
| `MEMSEARCH_SUMMARIZE_PORT` | no | `8494` | Override listen port |
| `MEMSEARCH_POLL_INTERVAL` | no | `10` | Poll cycle in seconds |
| `LOG_LEVEL` | no | `INFO` | Logging verbosity |
| `LOG_FILE` | no | — | Optional log file path |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | `http://localhost:4318` | OTLP HTTP endpoint for SigNoz |

## Security

- Path confinement: `memory_file` spool field restricted to `~/.claude/projects/` and `~/.memsearch/` only
- Prompt injection delimiters around transcript content before sending to the API

## Dependencies

- LLM provider for summarization calls — either the Anthropic API (external), or, with the
  live `provider = "ollama"` config, [ollama-queue-proxy](../ai-search/ollama-queue-proxy.md)
  at `127.0.0.1:11435`
- memsearch venv at `/opt/venvs/memsearch/` — Python runtime and FastMCP
- SigNoz OTEL collector (optional) — telemetry spans with model, token counts, latency

## Operations

```bash
pm2 logs memsearch-summarize --lines 50   # recent activity
pm2 restart memsearch-summarize            # restart service
```

Check spool status via MCP or by inspecting JSON files in spool directories directly.
Spool entries in `error` state need manual investigation — check the `error` field in the JSON.

Verified 2026-07-13: `~/logs/memsearch-summarize.log` shows recent `summarized` events and
all spool directories at 0 pending entries (caught up, not stuck) — an earlier research pass
the same day had flagged apparent inactivity since 2026-06-27, but the log has since resumed
writing.

## Related Docs

- [memory-services.md](memory-services.md) — memory service overview and dependency chain
- [memsearch.md](memsearch.md) — memsearch library and indexing
- [memsearch-mcp.md](memsearch-mcp.md) — semantic search MCP (consumers of summaries)
