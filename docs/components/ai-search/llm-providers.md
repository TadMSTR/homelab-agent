# LLM Providers

Which LLM each forge memory/search consumer actually calls, kept in one page because it kept
being wrong in four places at once (vikunja#402): memsearch's docs asserted Ollama/qwen3:14b
for over a month after the live config had moved to Mistral, and a diagram separately implied
qmd depended on Milvus when it does not. Read the live config yourself before citing anything
below — that is exactly the discipline whose absence produced this page.

memsearch itself was retired on 2026-09-17 ([memsearch.md](../memory/memsearch.md#retirement)).
Session digests are now written by [scribe](../memory/scribe.md) and semantic search is
[qmd](../memory/memory-services.md). The memsearch rows that used to fill the table below are
kept as a closed history note at the end of the page.

**Vendor facts (pricing, model lifecycle, rate limits, API surface) live in doc-cache-mcp, not
here.** Mistral is already cached there (auto-synced). Query it rather than restating vendor
numbers in this doc, which is how they drift out of date. This page holds only forge-specific
configuration decisions: what forge chose, and why.

## Consumer → provider table

Verified 2026-10-27 against scribe's live config file and qmd's model cache.

| Consumer | Provider | Model | Why | Fallback |
|---|---|---|---|---|
| scribe `[summarize.session]` (session digest writer, hourly cron) | Mistral, OpenAI-compatible (`https://api.mistral.ai/v1`) | `mistral-small-latest` | After scribe's deterministic extractor, the model only formats a structured event log; `small` is enough, about 10x cheaper than `medium`, and keeps the GPU free | None. The live config declares only `[providers.mistral]`. scribe's example config also shows an Ollama provider and a `[summarize.daily]` stage on `claude-cli`; forge omits both, because scribe resolves every declared stage's provider at load time |
| qmd embeddings | **Not Ollama, not OQP.** `llama.cpp` in-process, loading its own GGUF | `embeddinggemma-300M-Q8_0.gguf` from qmd's model cache (`~/.cache/qmd/models/`) | Independent in-process embedder — qmd has no dependency on Milvus, memsearch, or OQP | None needed; always available. See the GPU note below for its actual coupling |
| qmd reranking and query expansion | `llama.cpp` in-process, same as embeddings | `qwen3-reranker-0.6b-q8_0.gguf`, `qmd-query-expansion-1.7B-q4_k_m.gguf` | Bundled with qmd; no network hop | None needed |

[Ollama](ollama.md) (behind [ollama-queue-proxy](ollama-queue-proxy.md)) is no longer on the
memory pipeline's path. It still serves other clients; check `ollama list` and the OQP config
for what is loaded rather than inferring it from this page.

## The coupling the docs used to get backwards

[memory-architecture.md](../memory/memory-architecture.md) once drew
`memsearch-summarize → Anthropic API` and a `Milvus → qmd` dependency arrow. Both were stale —
the first predated even the Ollama era, the second was never true. qmd links `llama.cpp`
in-process and never touched Milvus, which is why retiring memsearch and Milvus left qmd's
vector search intact.

The coupling that diagram omitted is GPU sharing. **qmd's in-process `llama.cpp` and
Ollama's `llama.cpp`-backed inference are two uncoordinated consumers of the same 16 GB GPU.**
While memsearch was live, its `bge-m3` embedding calls through Ollama were the other half of
that contention, and the root of the recurring "Failed to create any embedding context"
errors. memsearch is gone, but the relationship is not: any workload that loads a model into
Ollama competes with qmd for VRAM. When qmd embedding errors reappear, look at what Ollama has
resident first; a data dependency between the two does not exist.

## Forge-specific decisions worth keeping visible

- **`mistral-small-latest` is run unpinned, not at a fixed dated version.** This accepts
  silent model and price changes on Mistral's schedule. Mistral's own model-lifecycle
  documentation (doc-cache-mcp) recommends pinning; forge has not done so. This is a decision
  to revisit, not an oversight — written down here so it can be.
- **scribe's output does have a quality gate.** A weekly `scribe qc-report` grades live digests
  against the event log the model was shown, with regression thresholds set from measured
  weeks. It replaced `memory-compact-qc`, which graded memsearch `compact` output
  ([memory-compact-qc.md](../memory/memory-compact-qc.md)).
- **There is no session-digest fallback provider.** If the Mistral API is down, the affected
  sessions are left `provisional` and retried on later runs (bounded at three attempts);
  `scribe recover` and a daily detector cover anything that never lands. See
  [scribe.md](../memory/scribe.md#provisional-digests-and-scribe-recover).

## History: memsearch providers (closed)

memsearch was the memory pipeline's only LLM consumer until its retirement on 2026-09-17. Its
provider history, for anyone reading older notes:

- **Session summaries** (`plugins.claude-code.summarize`): Anthropic API, then an
  Ollama-hosted `qwen3:14b` modelfile, then Mistral `mistral-medium-latest` from the 2026-08
  pipeline-resilience build until retirement. An `[llm.providers.ollama]` block stayed
  configured but unselected as a failover option (vikunja#399); it went with the rest of
  memsearch.
- **Library-level LLM calls** (`[llm]`, e.g. `compact`): Mistral `mistral-medium-latest`, the
  same cutover as summaries. `memsearch-spend.sh` metered only `compact`, never summaries, so
  spend figures quoted from it understated total pipeline LLM spend.
- **Embeddings** (`[embedding]`): Ollama `bge-m3` through ollama-queue-proxy, the one memsearch
  provider claim that stayed correct throughout.

## Related Docs

- [scribe.md](../memory/scribe.md) — the session digest writer and its provider config
- [memory-services.md](../memory/memory-services.md) — qmd and the indexing services
- [ollama.md](ollama.md) — Ollama backend
- [ollama-queue-proxy.md](ollama-queue-proxy.md) — queuing/auth layer in front of Ollama
- [memsearch.md](../memory/memsearch.md) — retired; retirement record
- [memory-architecture.md](../memory/memory-architecture.md) — full memory system map
