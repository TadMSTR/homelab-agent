# langfuse-mcp

Read-only FastMCP Python MCP server wrapping the Langfuse v2 API. Gives forge agents
structured access to LLM traces, generations, sessions, and cost data from the
`forge-agents` Langfuse project.

- **Version:** 0.1.1
- **Repo:** `TadMSTR/langfuse-mcp` (public)
- **Transport:** stdio via `run-langfuse-mcp.sh` (PM2-managed)
- **Port:** none — stdin/stdout only
- **Auth:** Basic Auth (`LANGFUSE_PUBLIC_KEY:LANGFUSE_SECRET_KEY` from `/opt/secrets/langfuse.env`)
- **Agents:** all 5 forge agents via scoped-mcp `langfuse` module

## Tools

| Tool | Description |
|------|-------------|
| `list_traces` | List LLM traces with optional filtering by session, user, or date range |
| `get_trace` | Fetch a specific trace by ID including all observations |
| `list_generations` | List LLM generation spans with model, token counts, and latency |
| `get_cost_summary` | Aggregate cost across all generations by model — paginates the full generation history |
| `list_sessions` | List traced sessions |
| `get_session` | Fetch all traces in a session |
| `list_scores` | List evaluation scores (evals, user feedback) |

## Cost Aggregation

`get_cost_summary` is the primary cost visibility tool. It paginates through all
generations in the project and aggregates token usage and estimated cost by model name.
This is intentionally read-only — it queries what Langfuse has already recorded from
agent sessions, not a live estimate.

## Launcher Pattern

langfuse-mcp runs as a stdio subprocess inside the scoped-mcp process, but stdio
subprocesses don't inherit the scoped-mcp environment. Credentials are delivered by
`~/scripts/run-langfuse-mcp.sh`, which sources `/opt/secrets/langfuse.env` before
exec-ing the langfuse-mcp binary:

```bash
set -euo pipefail
source /opt/secrets/langfuse.env
exec /opt/venvs/langfuse-mcp/bin/langfuse-mcp
```

This pattern is shared with other stdio-launched MCP servers where the scoped-mcp env
cannot be relied upon. See [forge-agent-mcp-restore.md](../phases/forge-agent-mcp-restore.md)
for background.

## scoped-mcp Registration

Registered in all 5 agent manifests as module type `mcp_proxy`, launched via the
`run-langfuse-mcp.sh` wrapper:

```json
{
  "name": "langfuse",
  "type": "mcp_proxy",
  "launch": "~/scripts/run-langfuse-mcp.sh"
}
```

## Observability

Structured logging (structlog, JSON-L) is always on. Logs go to **stderr and a file simultaneously** — no configuration required.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/langfuse-mcp/logs/langfuse-mcp.log` | Log file path. Default is baked in; override to redirect. |
| `LOG_LEVEL` | `INFO` | Structured log level. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Enable OTEL tracing (`pip install langfuse-mcp[otel]`). |
| `INFLUXDB_URL` + `INFLUXDB_TOKEN` | — | Enable InfluxDB metric emission (`pip install langfuse-mcp[observability]`). |
| `NATS_URL` | — | Enable NATS metric publishing (`pip install langfuse-mcp[observability]`). |

The log directory is created automatically on startup.

## Dragonfly Dependency

langfuse-mcp's connection to Langfuse is indirect — it queries the Langfuse HTTP API.
However, Langfuse ingestion (populating the data langfuse-mcp reads) depends on the
Langfuse Dragonfly queue accepting BullMQ keys, which requires `allow-undeclared-keys`
in the Dragonfly config. Without this flag, Langfuse cannot ingest traces and
langfuse-mcp returns empty results. See [langfuse.md](langfuse.md) for the Dragonfly
config details.

## Security

No dedicated security audit for the MCP server itself. Credentials are scoped to the
`forge-agents` Langfuse project (read-only API key pair), sourced from
`/opt/secrets/langfuse.env` (chmod 600). The server is read-only by design — no
Langfuse write operations are exposed as tools.

## Related Docs

- [langfuse.md](langfuse.md) — Langfuse service (the wrapped service)
- [forge-agent-mcp-restore.md](../phases/forge-agent-mcp-restore.md) — scoped-mcp wiring and launcher pattern
