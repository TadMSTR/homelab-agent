# AI Cost Tracking

The AI cost tracking pipeline gives visibility into Claude Code session activity and LibreChat usage — token counts, estimated costs, session durations, model breakdown — displayed in a unified Grafana dashboard. It's the observability layer for the [Layer 3](../../README.md#layer-3--multi-agent-claude-code-engine) agent engine.

The core problem it solves: Claude Code on a Pro or Max subscription always reports `costUSD: 0` in its JSONL transcripts. Tokens are tracked, but cost is suppressed. This pipeline parses the token data, applies a hardcoded pricing table, and ships the results to InfluxDB for dashboarding.

## Architecture

```
Claude Code JSONL transcripts         LibreChat Prometheus endpoint
(~/.claude/projects/*/transcripts/)   (http://127.0.0.1:3080/metrics)
              │                                      │
              ▼                                      ▼
  claude-cost-metrics.py            Telegraf prometheus input
  (Telegraf exec input, 5min)               │
              │                             │
              └─────────────┬───────────────┘
                            ▼
                 Local InfluxDB (claudebox-agent bucket)
                            │
                            ▼
                Grafana dashboard (grafana.yourdomain)
```

No new services are needed beyond what's already running. Telegraf handles scheduling for both the Python script and the LibreChat metrics scrape. The local Grafana + InfluxDB stack (see [grafana-claudebox](grafana-claudebox.md)) is the display layer.

## JSONL Parsing

Claude Code writes one `.jsonl` file per conversation in `~/.claude/projects/*/transcripts/`. Each line is a JSON event — user messages, assistant messages, tool use, results. The cost tracking script (`~/scripts/claude-cost-metrics.py`) processes these files to extract:

- Token usage per assistant message (`inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`)
- Session duration (timestamp of first message to last message)
- Model used
- Project context (derived from the directory path)

**Why `costUSD` isn't used:** On Claude Pro/Max subscriptions, every session reports `costUSD: 0` in the transcript metadata. Token counts are accurate, but cost is suppressed at the API level. The script applies a hardcoded pricing table to the token counts to derive an estimated cost. This needs manual updates when Anthropic changes pricing, but in practice pricing changes infrequently enough that this is acceptable for a personal dashboard.

**Watermark-based processing:** The script maintains a watermark at `~/.claude/logs/cost-watermark.json` — a map of file path to last-processed position. On each run, it skips fully-processed files and continues from the last position in partially-processed ones. This avoids re-reading the entire transcript corpus every 5 minutes.

**Output format:** InfluxDB line protocol written to stdout. Telegraf's exec input captures this and ships it to the local InfluxDB.

## Measurements

Two InfluxDB measurements in the `claudebox-agent` bucket:

**`claude_session`** — one record per conversation session:

| Field | Description |
|-------|-------------|
| `duration_s` | Session duration in seconds |
| `input_tokens` | Total input tokens (including cache reads) |
| `output_tokens` | Total output tokens |
| `cache_creation_tokens` | Tokens used for cache warming |
| `cache_read_tokens` | Tokens served from cache |
| `estimated_cost_usd` | Calculated from hardcoded pricing table |
| `message_count` | Number of assistant messages in session |

Tags: `model`, `project`

**`claude_cost`** — aggregated rolling totals (written on each run):

| Field | Description |
|-------|-------------|
| `total_input_tokens` | Cumulative input tokens |
| `total_output_tokens` | Cumulative output tokens |
| `total_estimated_cost_usd` | Cumulative estimated cost |
| `session_count` | Total sessions processed |

Tags: `model`

## Telegraf Configuration

Two new blocks added to `/etc/telegraf/telegraf.conf`:

```toml
# Claude Code cost metrics — exec input
[[inputs.exec]]
  commands = ["$HOME/scripts/claude-cost-metrics.py"]
  timeout = "30s"
  interval = "5m"
  data_format = "influx"
  name_prefix = ""

# LibreChat Prometheus metrics
[[inputs.prometheus]]
  urls = ["http://127.0.0.1:3080/metrics"]
  interval = "5m"
  metric_version = 2
  namepass = ["librechat_*"]

# Second output block — routes agent metrics to local InfluxDB
[[outputs.influxdb_v2]]
  urls = ["http://127.0.0.1:8086"]
  token = "$INFLUXDB_LOCAL_TOKEN"
  organization = "claudebox"
  bucket = "claudebox-agent"
  namepass = ["claude_*", "librechat_*"]
```

The `namepass` filter on the output block ensures that standard Telegraf system metrics (CPU, disk, network) continue flowing to the existing atlas InfluxDB output and don't get written to the local bucket. The two outputs coexist without interference.

`INFLUXDB_LOCAL_TOKEN` is set in `/etc/default/telegraf` — the value is the InfluxDB admin token from the grafana-claudebox stack's `.env` file.

## Dashboard

The Grafana dashboard at `grafana.yourdomain` covers:

- **Cost overview** — estimated daily/weekly/monthly spend, running total, cost by model
- **Token usage** — input vs. output vs. cache read vs. cache creation, session distribution
- **Session breakdown** — sessions by project, duration distribution, message count
- **LibreChat activity** — conversation volume, model usage, user activity (from Prometheus metrics)

All four panels share the same time range selector and update on the same Telegraf polling interval.

## Prerequisites

- Python 3.11+ (for the cost metrics script)
- Telegraf running on claudebox (already present if using the monitoring setup)
- Local Grafana + InfluxDB stack running — see [grafana-claudebox](grafana-claudebox.md)
- LibreChat running with metrics enabled (`transactions.enabled: true` in `librechat.yaml`)
- `INFLUXDB_LOCAL_TOKEN` set in `/etc/default/telegraf`

## Gotchas and Lessons Learned

**`costUSD` is always 0 on Pro/Max.** This isn't a bug in the script — it's how the Claude API reports costs for subscription-based access. The hardcoded pricing table is the only way to get estimated costs. Update it manually if Anthropic changes pricing.

**JSONL has no result messages.** The transcript format doesn't include a final summary event with total token counts. Totals have to be accumulated from individual assistant messages within the session. If a session is in progress, the watermark correctly handles partial files — the in-progress session's costs will be underreported until the session ends and the final messages are written.

**Cache tokens are cheap but not free.** Cache read tokens are priced significantly lower than input tokens (roughly 10x cheaper, depending on model). The pricing table tracks them separately and applies the correct rate. Don't lump all input tokens together — cache hit rate matters for cost accuracy.

**LibreChat Prometheus metrics require `transactions.enabled: true`.** If transactions are disabled, LibreChat still runs but the `/metrics` endpoint returns no cost or token data. The Telegraf prometheus input will scrape successfully but the dashboard panels that depend on LibreChat data will be empty.

**Watermark file location.** If you change the watermark path, update both the script and anything that might clear the log directory. The watermark file is small and inexpensive to lose — the script will reprocess all transcripts from scratch on the next run — but it will cause a one-time spike in InfluxDB writes.

## Standalone Value

The JSONL parsing script works without the rest of the agent stack. If you run Claude Code and want to understand your token usage and estimated costs, you can adapt the script to output CSV or print a summary to stdout without any Telegraf or InfluxDB dependency. The pricing logic and watermark-based processing are the useful parts.

The full pipeline — Telegraf exec → InfluxDB → Grafana — makes sense if you're already running monitoring infrastructure. If you're not, the simpler option is to run the script directly and pipe the output into a spreadsheet or a local SQLite database.

## Related Docs

- [grafana-claudebox](grafana-claudebox.md) — the display layer for this pipeline
- [LibreChat](librechat.md) — source of the Prometheus metrics
- [Architecture overview](../../README.md#layer-3--multi-agent-claude-code-engine) — Layer 3 agent engine context
