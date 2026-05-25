# langfuse-mcp

Read-only FastMCP Python MCP server wrapping the [Langfuse](https://langfuse.com) v2 API.
Gives forge's operator agents structured access to LLM observability data: trace history,
generation costs by model, session summaries, and quality scores. No write operations —
tracing is handled by SDK integration in each application, not through this MCP.

- **Source:** `~/repos/personal/langfuse-mcp/`
- **PM2 service:** `langfuse-mcp` (forge, stdio transport)
- **Status:** Phase 3 forge deployment in progress (helm-build)
- **Version:** 0.1.0
- **Security audit:** clean (0 findings)

## Tools

| Tool | Description |
|------|-------------|
| `list_traces` | Recent traces: id, name, timestamp, latency, cost, input/output preview |
| `get_trace` | Full trace by ID — all spans, observations, token counts, model |
| `list_generations` | LLM generation events with prompt/completion tokens and cost |
| `get_cost_summary` | Aggregate cost + tokens grouped by model for a time range |
| `list_sessions` | Recent sessions with trace count and aggregate cost |
| `get_session` | All traces in a session, in chronological order |
| `list_scores` | Quality scores attached to traces (accuracy, helpfulness, etc.) |

## Cost Analysis Workflow

`get_cost_summary` is a client-side aggregation tool — it paginates
`/api/public/generations` and groups results by model client-side. It is the primary
entry point for cost monitoring:

```
1. get_cost_summary(from_timestamp="2026-05-01T00:00:00Z")
   → totals by model: call_count, prompt_tokens, completion_tokens, total_cost

2. list_generations(model="claude-sonnet-4-6", from_timestamp="2026-05-01T00:00:00Z")
   → individual generation events for drill-down

3. list_traces(from_timestamp="2026-05-01T00:00:00Z")
   → find expensive traces by totalCost

4. get_trace(trace_id)
   → full span tree to identify which step drove the cost
```

## Security Model

All tool calls use GET requests only — no POST, PUT, or DELETE operations are implemented.
Public and secret keys are injected as environment variables and never appear in tool
arguments, responses, or logs. The MCP has no access to Langfuse admin operations, project
management, or the Langfuse database directly.

## Environment Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `LANGFUSE_BASE_URL` | yes | `http://localhost:3000` | Langfuse API base URL |
| `LANGFUSE_PUBLIC_KEY` | yes | — | Langfuse public key (`pk-lf-...`) |
| `LANGFUSE_SECRET_KEY` | yes | — | Langfuse secret key (`sk-lf-...`) |
| `LANGFUSE_DEFAULT_PROJECT_ID` | no | — | Default project filter |
| `LOG_LEVEL` | no | `INFO` | structlog verbosity |
| `LOG_FILE` | no | — | Log to file path; stdout if unset |
| `INFLUXDB_URL` | no | — | Enables InfluxDB telemetry when set |
| `INFLUXDB_TOKEN` | no | — | InfluxDB auth token |
| `INFLUXDB_BUCKET` | no | `langfuse-mcp` | InfluxDB bucket name |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | — | Enables OTEL traces when set |
| `NATS_URL` | no | — | Enables NATS event publishing when set |
| `NATS_SUBJECT_PREFIX` | no | `langfuse` | NATS subject prefix |

**Getting API keys:** Langfuse UI → Settings → API Keys → Create new key pair.
Copy `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` to `~/.secrets/forge.env`.

**Getting project ID:** Langfuse UI → Settings → Projects → copy the UUID.

## Deployment

```bash
cd ~/repos/personal && git clone <repo-url> langfuse-mcp
cd langfuse-mcp
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# Add LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY to ~/.secrets/forge.env

pm2 start ecosystem.config.js --env-file ~/.secrets/forge.env
pm2 save
```

## Observability

| Feature | Default | Enable with |
|---------|---------|-------------|
| Structured JSON logging | **ON** | `LOG_LEVEL`, `LOG_FILE` |
| InfluxDB telemetry | off | `INFLUXDB_URL` |
| OTEL traces | off | `OTEL_EXPORTER_OTLP_ENDPOINT` |
| NATS publishing | off | `NATS_URL` |

## Related Docs

- [langfuse.md](langfuse.md) *(helm-platform)* — the Langfuse service this wraps
- [dockhand-mcp.md](dockhand-mcp.md) — companion Docker management MCP
- [patchmon-mcp.md](patchmon-mcp.md) — companion apt patch management MCP
