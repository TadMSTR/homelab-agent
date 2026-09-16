# LLM Providers

Which LLM each forge memory/search consumer actually calls, kept in one page because it kept
being wrong in four places at once (vikunja#402): memsearch's docs asserted Ollama/qwen3:14b
for over a month after the live config had moved to Mistral, and a diagram separately implied
qmd depended on Milvus when it does not. Read the live config yourself before citing anything
below — that is exactly the discipline whose absence produced this page.

**Vendor facts (pricing, model lifecycle, rate limits, API surface) live in doc-cache-mcp, not
here.** Mistral is already cached there (6 topics / 48 chunks, auto-synced) — query it rather
than restating vendor numbers in this doc, which is how they drift out of date. This page
holds only forge-specific configuration decisions: what forge chose, and why.

## Consumer → provider table

| Consumer | Provider | Model | Why | Fallback |
|---|---|---|---|---|
| memsearch `plugins.claude-code.summarize` (session digest writer) | Mistral, OpenAI-compatible (`https://api.mistral.ai/v1`) | `mistral-medium-latest` | Replaced an Ollama-hosted `qwen3:14b` modelfile during the 2026-08 pipeline-resilience build for quality/cost balance | None automatic. `[llm.providers.ollama]` remains configured in `~/.memsearch/config.toml` but unselected — pending the failover decision at vikunja#399, not dead config |
| memsearch `[llm]` (default library-level LLM calls, e.g. `compact`) | Mistral, OpenAI-compatible | `mistral-medium-latest` | Same cutover as summarize | Same — see #399 |
| memsearch `[embedding]` | Ollama, via [ollama-queue-proxy](ollama-queue-proxy.md) (`127.0.0.1:11435`, native Ollama API, no `/v1`) | `bge-m3` | GPU-local, no external call, OQP serializes concurrent embedding requests across all its clients | None needed — OQP handles queuing; this is the one Ollama claim in the memory docs that has stayed correct throughout the Mistral cutover |
| qmd embeddings | **Not Ollama, not OQP.** `llama.cpp` in-process, loading its own GGUF | `embeddinggemma-300M-Q8_0.gguf` from `~/.cache/qmd/models/` | Independent in-process embedder — qmd has no dependency on Milvus, memsearch, or OQP at all | None needed — always available; see the GPU note below for its actual coupling |

## The coupling the docs used to get backwards

[memory-architecture.md](../memory/memory-architecture.md) previously drew
`memsearch-summarize → Anthropic API` and a `Milvus → qmd` dependency arrow. Both were stale —
the first predates even the Ollama era, the second was never true. qmd links `llama.cpp`
in-process and never touches Milvus; retiring memsearch would not take qmd's vector search
with it (source:
`host-forge-design-records/2026-07-25-qmd-embeds-in-process-outside-ollama-proxy.md`).

The coupling that diagram omitted, and the one that actually matters operationally: **qmd's
in-process `llama.cpp` and Ollama's `llama.cpp`-backed inference (serving memsearch's `bge-m3`
embedding calls) are two uncoordinated consumers of the same RTX 2000 Ada, 16 GB VRAM.** That
contention — not a data dependency between qmd and memsearch — is the root of the recurring
"Failed to create any embedding context" errors on forge. If one of those pages is ever
retired, the GPU-sharing relationship is what to re-examine, not the (nonexistent) Milvus link.

## Forge-specific decisions worth keeping visible

- **`mistral-medium-latest` is run unpinned, not at a fixed dated version.** This accepts
  silent model and price changes on Mistral's schedule. Mistral's own model-lifecycle
  documentation (doc-cache-mcp) recommends pinning; forge has not done so. This is a decision
  to revisit, not an oversight — written down here so it can be.
- **The summarize path has no quality gate.** `memory-compact-qc.sh` grades `compact` output,
  not summarize output, and grades it for fidelity to a source that is itself summarize
  output. Do not read [memory-architecture.md](../memory/memory-architecture.md)'s hop table
  as implying summarize has independent quality coverage — it does not.
- **`memsearch-spend.sh` meters only `process=compact`.** Mistral summarize calls are not in
  that meter, so any spend figure quoted from it (e.g. "$0.13 of $30") is not total pipeline
  LLM spend — it excludes the summarize path entirely.
- **Do not delete the `[llm.providers.ollama]` block from memsearch config or docs.** It is
  configured-but-unselected, kept for the failover decision at vikunja#399. Treating it as
  dead config and removing it would foreclose that decision rather than defer it.

## Related Docs

- [ollama.md](ollama.md) — Ollama backend
- [ollama-queue-proxy.md](ollama-queue-proxy.md) — queuing/auth layer in front of Ollama
- [memsearch.md](../memory/memsearch.md) — embedding config and the summarize plugin
- [memsearch-summarize.md](../memory/memsearch-summarize.md) — the summarize service itself
- [memory-architecture.md](../memory/memory-architecture.md) — full memory system map
