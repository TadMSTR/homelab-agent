# memsearch-summarize

Session transcript summarizer that polls memsearch spool directories, calls the Anthropic API
to generate bullet-point summaries, and replaces raw transcripts in memory files. Also exposes
a FastMCP MCP server for on-demand summarization.

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
3. Calls Anthropic Messages API (claude-sonnet-4-6) to summarize the transcript into 3–6 bullet points
4. Replaces the raw transcript in the memory file with the summary
5. Marks the spool entry as `ok` (success), `retry` (transient failure), or `error` (permanent failure)

Rate limit handling: on HTTP 429, backs off to 3× the poll interval before retrying.

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
| `plugins.claude-code.summarize.model` | `claude-sonnet-4-6` | LLM model for summarization |
| `plugins.claude-code.summarize.enabled` | `true` | Enable/disable summarization |
| `prompts.summarize` | built-in | Path to custom prompt file (optional) |

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `ANTHROPIC_API_KEY` | yes | — | API access (injected by launcher from forge.env) |
| `MEMSEARCH_SUMMARIZE_PORT` | no | `8494` | Override listen port |
| `MEMSEARCH_POLL_INTERVAL` | no | `10` | Poll cycle in seconds |
| `LOG_LEVEL` | no | `INFO` | Logging verbosity |
| `LOG_FILE` | no | — | Optional log file path |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | `http://localhost:4318` | OTLP HTTP endpoint for SigNoz |

## Security

- Path confinement: `memory_file` spool field restricted to `~/.claude/projects/` and `~/.memsearch/` only
- Prompt injection delimiters around transcript content before sending to the API

## Dependencies

- Anthropic API (external) — for summarization calls
- memsearch venv at `/opt/venvs/memsearch/` — Python runtime and FastMCP
- SigNoz OTEL collector (optional) — telemetry spans with model, token counts, latency

## Operations

```bash
pm2 logs memsearch-summarize --lines 50   # recent activity
pm2 restart memsearch-summarize            # restart service
```

Check spool status via MCP or by inspecting JSON files in spool directories directly.
Spool entries in `error` state need manual investigation — check the `error` field in the JSON.

## Related Docs

- [memory-services.md](memory-services.md) — memory service overview and dependency chain
- [memsearch.md](memsearch.md) — memsearch library and indexing
- [memsearch-mcp.md](memsearch-mcp.md) — semantic search MCP (consumers of summaries)
