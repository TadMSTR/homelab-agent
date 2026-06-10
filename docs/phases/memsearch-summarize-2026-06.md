# memsearch-summarize-2026-06

**Status:** Complete
**Date:** 2026-06-01
**Agents:** developer (build), sysadmin (deploy)

## Summary

Built and deployed memsearch-summarize — a Python PM2 service and FastMCP MCP server that
automatically summarizes raw memsearch session transcripts via the Anthropic API. Replaces
verbose Claude Code session logs with concise bullet-point summaries in memory files.

## What Was Built

- **Summarizer daemon** — polls `~/.memsearch/spool/` and per-project spool dirs every 10s,
  calls claude-sonnet-4-6 to produce 3–6 bullet summaries, writes them back to memory files
- **FastMCP MCP server** — three tools (`spool_status`, `summarize_pending`, `summarize_turn`)
  on port 8494, streamable-http transport
- **Launcher wrapper** — `run-memsearch-summarize.py` injects `ANTHROPIC_API_KEY` from
  `~/.secrets/forge.env` and execs under `/opt/venvs/memsearch/bin/python3`

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| MCP server (Phase 2) made required, not optional | Needed for scoped-mcp metrics access |
| Model upgraded from Haiku to Sonnet | Quality — Haiku summaries lost important context; Langfuse will monitor costs |
| Path confinement on `memory_file` spool field | Medium security finding — prevents path traversal to arbitrary files |
| Prompt injection delimiters added | Low security finding — fences transcript content before API call |

## Security

Audit completed as part of the build workflow. Key findings addressed:

- **Medium (FW-02):** Path confinement added — `memory_file` restricted to `~/.claude/projects/` and `~/.memsearch/`
- **Low:** Prompt injection delimiters added around transcript content

No critical or high findings.

## Deployment

- PM2 service `memsearch-summarize` (ID 38), always-on
- `opentelemetry-exporter-otlp-proto-http` installed in `/opt/venvs/memsearch/`
- Port 8494 registered in `host-forge/services.md` and `host-forge/pm2-services.md`
- PR #1 squash-merged to `host-forge-scripts`

## Artifacts

- Script: `~/repos/gitea/host-forge-scripts/scripts/memsearch-summarize.py`
- Launcher: `~/repos/gitea/host-forge-scripts/scripts/run-memsearch-summarize.py`
- Component doc: `docs/components/memsearch-summarize.md`
