# memsearch-summarize (retired 2026-09-17)

memsearch-summarize was the session transcript summarizer: it polled memsearch spool
directories, called a configured LLM provider (Anthropic, then Ollama, then Mistral — the
provider changed twice over its lifetime) to generate bullet-point summaries, and replaced
raw transcripts in memory files. It ran as an always-on PM2 process on port 8494.

## Retirement

Retired 2026-09-17, part 3 of `memory-consolidation-2026-09` (vikunja#863) — see
[memsearch.md](memsearch.md#retirement) for the full cutover record.

**Replaced by [scribe](scribe.md).** The root cause: memsearch-summarize's input pipeline
(`parse-transcript.sh :: format_turn()`) kept only user and assistant text, discarding
`tool_use`/`tool_result`/`thinking` — 6.5% of a session reached the model, which was then
asked to cite tool names and file names it had never seen. This had twice been misdiagnosed
as a model quality problem (closed as "reverted to Claude API as stopgap") before scribe's
build traced it to the extraction layer. Scribe fixes the input: a deterministic extractor
produces a structured event log first, and a schema'd summarizer consumes that instead of
raw transcript text.

Telemetry continuity: scribe deliberately emits spans under the same names
(`memsearch.summarize`, `memsearch.summarize_rejected`, `memsearch.summarize_extract`) so
existing SigNoz dashboards built against this service's telemetry keep working — though the
exporter transport changed (HTTP → gRPC), so historical continuity is unconfirmed
(vikunja#865).

## What it was

- **PM2 name:** `memsearch-summarize`, port 8494, `127.0.0.1`, streamable-http
- **Script:** `~/repos/gitea/host-forge-scripts/scripts/memsearch-summarize.py`
- **Poll interval:** 10 seconds, `~/.memsearch/spool/`
- **Live provider at retirement:** `mistral-medium-latest` via `[llm.providers.mistral]`

## Related Docs

- [scribe.md](scribe.md) — the replacement: deterministic extraction + schema'd summarization
- [memsearch.md](memsearch.md) — the library this service was part of, retired the same day
- [memory-services.md](memory-services.md) — current PM2 memory service list
