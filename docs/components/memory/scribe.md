# scribe

Deterministic transcript extractor and session summarizer, built to replace
[memsearch-summarize](memsearch-summarize.md)'s spool path. **Built and shadow-tested, not
deployed** — no PM2 process, no container, nothing listening. `memsearch-summarize` is
untouched and remains in production. See the repo README for full usage; this page covers
what an operator of the memory pipeline needs to know.

Repo: `TadMSTR/scribe` (private) — `~/repos/personal/scribe/README.md`.

## Why it exists

Memory summaries have been poor for months, and it was twice diagnosed as a model problem
(#174, #242, both closed as "reverted to Claude API as stopgap"). It was not a model problem.
`parse-transcript.sh :: format_turn()` keeps only user text and assistant text and skips
`tool_use`, `tool_result` and `thinking` — so **33,995 of 523,546 characters, 6.5% of a
session, reached the LLM** — and the prompt then instructed that model to "mention file names,
function names, tool names, and concrete outcomes." Demanding a class of fact that has been
removed from the input is a hallucination incentive. It also explains why Ollama looked worse
than Mistral: identical starvation, less capacity to fail gracefully.

Scribe fixes the input, not the model. A deterministic extractor turns the transcript into a
structured event log — tool name, bounded argument digest, exit status, files touched, with
redaction applied at extraction time — and a schema'd summarizer consumes that.

## Numbers worth knowing

Measured across the real 429-transcript, 596 MB corpus on forge:

- 47,270 tool events extracted; 0 orphaned results, 0 unparsable records.
- 8,015 secret-shaped values redacted, in 324 of 429 transcripts (76%). Redaction runs at
  extraction time.
- Whole-corpus summarization costs about $2.14/month at `mistral-small` pricing, against a
  $30 allowance. This is a context-window control more than a cost control — the largest
  session reaches ~68K tokens against `mistral-small`'s 128K context.

## Entry points

CLI only: `python -m scribe {extract|qc|run}`.

- `python -m scribe.extract <transcript.jsonl>` — run the extractor standalone.
- `python -m scribe qc --digest D --events E` — the groundedness gate; exits non-zero on an
  ungrounded digest.
- `python -m scribe run` — **defaults to a dry run.** Discovers finished sessions, extracts
  and reports, without constructing a provider, reading a credential, or writing anything.
  `python -m scribe run --live` runs the full shadow pipeline: summarize and write.

Port 8499 appears in `scribe.example.toml` but **no HTTP server exists** — that block is
forward-looking. Do not add 8499 to `services.md`.

## Session dating and the QC gate

Two behaviours worth knowing if you read a run's output:

- **Digests are filed under the session's own date** (`ended_at`, falling back to
  `started_at`, then the clock) — not the wall clock. This is what makes a backfill produce
  one file per day instead of collapsing many sessions into one file named for the run day.
- **The groundedness gate classifies backticked spans by shape**, not by treating every one as
  a command. Claims are checked against the serialized event log the model was actually shown,
  requiring a composed span's tokens to co-occur within 120 characters. A `groundedness_rate`
  of 0.00 on a real digest is a classifier bug, not evidence of fabrication, and should not
  recur under the current gate.

## Run totals and `placeholders`

A run's totals satisfy `written == summarized + suppressed + placeholders`. `placeholders` is
the field to watch: `written` counts every block that reached the file, and a placeholder is a
block, so before this field existed a run that silently lost summaries reported the same
`written` as a clean run. `python -m scribe run` prints a loud line when `placeholders` is
non-zero. **A non-zero value means summaries were lost, not degraded.**

The digest schema declares its own per-field limits to the model (`maxItems` plus the limits
stated in the system prompt) rather than enforcing an unstated rule after the fact — a
declared-but-unenforced limit used to cause the model to comply and still get rejected. A
schema violation from an over-long list is no longer retried; it fails fast rather than
burning three identical high-token calls before writing a placeholder.

## The backfill is not ready

Widening the shadow run beyond the initial 5 sessions has not happened. Treat the backfill as
**unblocked, not attempted** — the schema-cap defect that blocked it is fixed, but clearing a
blocker is not the same as being ready.

## Filesystem and permissions

- Read-only on `~/.claude/projects/*/*.jsonl` — asserted in tests on both content and mtime.
- Everything scribe creates is owner-only (0700 dirs, 0600 files), because transcripts are
  0600 and derived content must not be published wider than its source.
- Config is `scribe.toml`; `api_key` must be an env reference and a literal is refused at load.

## Dependencies

- A configured LLM provider for the session-digest stage — `mistral-small-latest` by default,
  or [ollama-queue-proxy](../ai-search/ollama-queue-proxy.md) at `127.0.0.1:11435` if
  configured to use Ollama. Daily roll-up uses `claude -p` (no API key).
- `~/.claude/projects/*/*.jsonl` transcripts — read-only.

**Do not copy the provider claims from [memory-architecture.md](memory-architecture.md) or
[memsearch-summarize.md](memsearch-summarize.md).** Both are currently wrong about the LLM
provider (vikunja#402, still open). If this page needs to restate the provider, derive it from
`scribe.example.toml` in the repo, not from those pages.

## Related tickets

- vikunja#843 — the original defect this component fixes. Open until cutover.
- vikunja#845 — repo-conform B14 regex gap, filed during the build, unrelated to scribe's
  function.
- vikunja#846 — `memsearch-spend.sh` reads a log nothing writes, so forge's Mistral spend has
  been under-reported by roughly half. Worth a cross-reference from memory-pipeline cost
  documentation.

## Related Docs

- [memsearch-summarize.md](memsearch-summarize.md) — the component scribe is built to replace
- [memory-architecture.md](memory-architecture.md) — full system overview
- Repo README: `~/repos/personal/scribe/README.md`
