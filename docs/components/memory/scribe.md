# scribe

Deterministic transcript extractor and session summarizer, built to replace
[memsearch-summarize](memsearch-summarize.md)'s spool path. **Released (v0.1.0), backfilled,
not cut over** — venv installed at `/opt/venvs/scribe`, a one-time backfill has populated
digests and event logs on disk, but there is no PM2 process, no cron, and the `SessionStart`
hook is not registered in `~/.claude/settings.json`. `memsearch-summarize` is untouched and
remains in production. See the repo README for full usage; this page covers what an operator
of the memory pipeline needs to know.

Repo: `TadMSTR/scribe` (private) — `~/repos/personal/scribe/README.md`. Tag `v0.1.0`.

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
- The backfill measured 436 sessions discovered, 49,000 tool events, ~$1.63 one-time and
  ~$1.57/mo steady state. As of this backfill, 174 digests exist across 9 agent directories,
  with 439 persisted event logs.

## Three tiers, and how to get between them

What scribe keeps is layered by cost, and each layer is reachable from the one above it:

| Tier | Where | Size per session | Indexed |
|---|---|---|---|
| **Digest** — what happened | `~/.local/share/scribe/digests/<agent>/<date>.md` | ~2 KB | yes — qmd `session-digests` |
| **Event log** — the evidence | `~/.local/share/scribe/eventlogs/<session-id>.json` | ~190 KB | **no** |
| **Raw transcript** — everything | `~/.claude/projects/*/*.jsonl`, and Backrest | ~2.5 MB | no |

The event log is written **before** the summarization call, so a run whose model call failed
still leaves a complete record of what it saw — this is what makes a digest re-checkable after
the fact; `scribe qc` needs it and previously nothing kept it.

Event logs are deliberately **not** indexed and live in a sibling directory rather than under
`digests/`, so that stays true by construction. They are evidence reached *from* a digest, not
a search target; indexing ~39 MB of tool arguments would swamp the digest signal in every
semantic query. They are also the least redacted thing scribe keeps, so they are 0600 inside a
0700 directory like everything else scribe writes.

Config key: `[discovery] eventlog_dir`, defaulting to `~/.local/share/scribe/eventlogs`. It
must stay a **sibling** of `output_dir`, never a child — the qmd collection globs
`<output_dir>/**/*.md`.

Drill-down is a lookup, not a search — every digest block carries its session id in the anchor
comment above it:

```bash
python -m scribe events <session-id>            # print the event log
python -m scribe events <session-id> --path     # just the path, for piping
python -m scribe qc --digest D --events "$(python -m scribe events ID --path)"
```

Retention is settled: **keep everything**. 429 sessions in ~39 MB, ~0.46 GB/year. No pruning
exists and none is planned.

**Digests are not mirrored to atlas** by `memory-archive-mirror.sh` under this layout. If that
durability is wanted it is an explicit choice nobody has made yet — a known gap, not an
assumed backup.

## Digests are indexed

The `session-digests` qmd collection exists as of 2026-09-15 (`host-forge-scripts` `index.yml`,
commit `79dbae4`), rooted at `~/.local/share/scribe/digests` with pattern `**/*.md` only —
`eventlogs/` is a different root, so the exclusion is structural, not pattern-dependent.
Retrieval verified live on qmd 2.8.3: 174 documents, `needsEmbedding: 0`, a `type: "vec"` query
returns digests across agents with scores 0.99 → 0.56.

Digests are deliberately **not** under `~/.claude/memory/` despite that being the cheaper
option: `memory-sync-weekly.sh` runs Opus over that tree with `--add-dir
--dangerously-skip-permissions`, and its brief includes merging duplicate notes and expiring by
category. A machine-generated corpus does not belong in a directory an LLM is instructed to
prune.

A document count is not evidence of retrievability — the collection reported 174 documents
while vector search still reached exactly 1 until embeddings were built (`qmd embed`). Verify
by querying, not by counting.

## Feeding the SessionStart injection

scribe also **pushes** a digest, rather than only being retrievable. `python -m scribe journal`
emits the JSON a Claude Code `SessionStart` hook writes to stdout, built from an agent's two
most recent digests; `hooks/session-start.sh` in the scribe repo is the wrapper to register.

This matters because the `SessionStart` injection is the **only** memory push surface
confirmed to reach a CloudCLI agent session — measured live 2026-09-15, a hook emitting
`hookSpecificOutput.additionalContext` is surfaced to the agent, while the sibling
`user-prompt-submit.sh` hook (see [memsearch.md](memsearch.md)) emits a bare `systemMessage`
that CloudCLI drops for agent sessions. Ted sees the latter only in his own terminal, which is
how that gap (vikunja#853) went unnoticed; Ted's call is that it closes on cutover rather than
being fixed separately.

The format needed no porting: the incumbent consumer's awk parser was extracted verbatim and
run over a real scribe digest, producing 177 lines of clean output, unmodified — only the
directory differed. That parser is kept byte-for-byte in the repo at
`tests/reference/recent_memory_preview.awk` and held to equality with scribe's Python port.

**Agent attribution comes from the session's `cwd`**, not from the flattened Claude Code
transcript-directory name. The transcript-directory encoding is lossy — a separator and a
hyphen both collapse to `-` — and was truncating three of forge's ten agents on the *write*
side (`doc-health` → `doc`, `helm-build` → `helm`, `memory-sync` → `memory`), which would have
left their injections permanently and silently empty. If this or another doc states a
`<agent>/` path derived from the transcript directory name, it is stale.

**Status:** confirmed live on this host — the `SessionStart` hook is registered only for
`core-context.md`/`directives.md` (`~/.claude/settings.json`), not scribe's. Registration is
part 3 of the `memory-consolidation-2026-09` programme (vikunja#863), sequenced after the
backfill (already complete — see above) so no agent sees an empty injection on cutover day.

## Entry points

CLI only: `python -m scribe {extract|events|journal|qc|run}`.

- `python -m scribe.extract <transcript.jsonl>` — run the extractor standalone.
- `python -m scribe events <session-id> [--path]` — print or locate a persisted event log.
  Exit 1 "none kept" is distinct from exit 2 "could not look."
- `python -m scribe journal` — emit the `SessionStart` hook payload for the calling agent.
- `python -m scribe qc --digest D --events E` — the groundedness gate; exits non-zero on an
  ungrounded digest. Now reads through the classifier described below for `post_render`
  fires.
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

**The post-render redaction guard now states a cause, not just a fire (vikunja#856).** A fire
used to be reported as proof extraction had missed something and told the reader to
investigate `redact.py` — it could not know that from a single fire. It now consults the
persisted event log and classifies each fire as `extraction-miss` / `model-output` /
`undetermined`. "There is no log" supports neither cause; treat `undetermined` accordingly
rather than assuming the worse (or better) reading.

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

## Filesystem and permissions

- Read-only on `~/.claude/projects/*/*.jsonl` — asserted in tests on both content and mtime.
- Everything scribe creates is owner-only (0700 dirs, 0600 files), because transcripts are
  0600 and derived content must not be published wider than its source. This includes the
  event log tier, which is the least redacted artefact scribe keeps.
- Config is `scribe.toml`; `api_key` must be an env reference and a literal is refused at load.

## Telemetry

Off by default. Spans are emitted only when **both** are true:

```sh
pip install 'scribe[telemetry]'          # the extra
export OTEL_EXPORTER_OTLP_ENDPOINT=...   # the endpoint (forge: http://127.0.0.1:4317)
```

**Neither alone does anything**, and getting it half right fails silently — this is the same
failure family forge has shipped twice before (vikunja#336: endpoint set, extra never
installed, dead two months; #579: extras not part of `venv-deploy`, dropped again on redeploy).
scribe prints a warning to stderr when the endpoint is set and the packages are missing, so the
half-configured case is now noisy. Installing the extra and setting the endpoint is still not
sufficient by itself, either — `trace.get_tracer()` returns a no-op tracer until an SDK
`TracerProvider` is installed; scribe's `run` does that itself, so there is no third
configuration step for an operator.

Three spans, deliberately named after the **incumbent's** so existing SigNoz dashboards survive
the cutover: `memsearch.summarize`, `memsearch.summarize_rejected`, `memsearch.summarize_extract`.
OTLP over gRPC — the endpoint is the collector's 4317, with no `/v1/traces` suffix. Whether
those dashboards actually have historical data at this endpoint is unconfirmed (vikunja#865):
the incumbent `memsearch-summarize` exports over HTTP, not gRPC.

## The backfill

The initial backfill is done: 436 sessions discovered, 174 digests written across 9 agent
directories (developer, doc-health, memory-sync, research, security, steward, sysadmin,
writer, plus `unknown` for unresolvable attribution), 439 event logs persisted. ~96% complete
— vikunja#868 tracks 9 sessions lost and 10 suppressed by a contamination guard that
false-positives on any angle-bracketed word; the state DB marks them `summarized` (terminal,
will not retry).

## Dependencies

- A configured LLM provider for the session-digest stage — `mistral-small-latest` by default,
  or [ollama-queue-proxy](../ai-search/ollama-queue-proxy.md) at `127.0.0.1:11435` if
  configured to use Ollama. Daily roll-up uses `claude -p` (no API key).
- `~/.claude/projects/*/*.jsonl` transcripts — read-only.
- qmd (`session-digests` collection) for digest retrieval; `qmd-refresh.sh` (hourly cron) for
  keeping it current.

**Do not copy the provider claims from [memory-architecture.md](memory-architecture.md) or
[memsearch-summarize.md](memsearch-summarize.md).** Both were wrong about the LLM provider
(vikunja#402); see those pages' own corrections. If this page needs to restate the provider,
derive it from `scribe.example.toml` in the repo.

## Related tickets

- vikunja#843 — the original defect this component fixes. Open until cutover.
- vikunja#845 — repo-conform B14 regex gap, filed during the build, unrelated to scribe's
  function.
- vikunja#846 — `memsearch-spend.sh` reads a log nothing writes, so forge's Mistral spend has
  been under-reported by roughly half. Worth a cross-reference from memory-pipeline cost
  documentation.
- vikunja#850, #856 — closed by the release-readiness build.
- vikunja#853 — SessionStart vs UserPromptSubmit injection asymmetry; closes on cutover.
- vikunja#863 — retirement/cutover build (memsearch removal, hook registration). Not yet
  queued.
- vikunja#865 — SigNoz dashboard continuity across the gRPC/HTTP exporter change, unconfirmed.
- vikunja#868 — ~4% of the backfill lost or suppressed; terminal, will not retry.

## Related Docs

- [memsearch-summarize.md](memsearch-summarize.md) — the component scribe is built to replace
- [memsearch.md](memsearch.md) — the `UserPromptSubmit` injection hook scribe does not touch
- [memory-architecture.md](memory-architecture.md) — full system overview
- Repo README: `~/repos/personal/scribe/README.md`
