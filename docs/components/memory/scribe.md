# scribe

Deterministic transcript extractor and session summarizer. It replaced
[memsearch-summarize](memsearch-summarize.md) on cutover, 2026-09-17
(`memory-consolidation-2026-09` part 3, vikunja#863): `memsearch-summarize` and the rest of the
memsearch stack are retired, and scribe's own `SessionStart` hook is now the live injection
feed. It runs as an hourly cron (`40 * * * *`, `flock -n`), not a PM2 daemon — see the internal
`pm2-services.md` cron table for the schedule. See the repo README for full usage; this page
covers what an operator of the memory pipeline needs to know.

Repo: `TadMSTR/scribe` — `~/repos/personal/scribe/README.md`. **Private today**; a public
release is in preparation and has not happened yet, so treat the repo as unreadable outside
forge until that flip is confirmed. Tag **v0.11.0**, confirmed deployed at `/opt/venvs/scribe`
(`pip show scribe` → `0.11.0`, live 2026-09-24). Merged and released is not automatically
deployed for this repo — check the running venv rather than trusting a build's own completion
note or a version pinned to a date in this doc; four releases shipped 2026-09-18 alone (v0.5.0
→ v0.6.0 → v0.7.0 → v0.8.0), v0.8.1 and v0.9.0 followed the next day (2026-09-19), and v0.10.0
and v0.11.0 both shipped 2026-09-24.

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

## Compaction boundaries are not user text (v0.6.0)

At a compaction boundary, Claude Code writes two records; the second is `type: user` with
`isCompactSummary: true`, whose content is the model's own recap of the conversation, not
anything a person typed. Before v0.6.0 the parser had no handling for it and read it as an
ordinary user turn — measured on one real session, 18,859 characters of machine-generated recap
entered the event log as user text, in the worst-degraded session in the corpus, where the
byte-budget ladder is forbidden from dropping real tool events (invariant 6) and so the recap
displaced evidence rather than the reverse.

The guard sits alongside `isMeta` and `_INJECTED_PREFIXES` — a third member of the same family
of machine-generated text that arrives structurally indistinguishable from a person speaking.
Prevalence measured across the full 451-transcript corpus: 2 transcripts (0.4%), both
interactive; headless dispatcher-launched sessions are single-task and never approach the
compaction threshold. **`turns` drops by one** on any transcript carrying a compact boundary —
the record was opening its own turn — and `stats.skipped_compact` reports when the guard fires,
so a zero is distinguishable from "no boundary present." `SCHEMA_VERSION` did not move; the
field is additive with a default.

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

Retention is settled: **keep everything, by decision, not by omission** (Ted, 2026-09-24,
vikunja#954; `AGENTS.md` invariant 18). After Claude Code's own 30-day transcript expiry, the
event log is the only surviving source a digest can be re-summarized from — a retention knob
that pruned it would quietly turn a recoverable loss into an unrecoverable one. 429 sessions in
~39 MB, ~0.46 GB/year; growth is watched outside scribe, not by scribe itself (sysadmin,
vikunja#965). No pruning exists and none is planned; if a retention setting is ever added, it
must default off and every deletion must be counted in the run totals (invariant 13).

**Digests are not mirrored to atlas** by `memory-archive-mirror.sh` under this layout. If that
durability is wanted it is an explicit choice nobody has made yet — a known gap, not an
assumed backup.

## The indexer contract, and why qmd isn't a dependency (v0.10.0)

Nothing in `src/` imports or knows about qmd; forge's use of it is a configuration choice, not
a dependency. As of v0.10.0 (`scribe-indexer-portability-2026-09`, vikunja#891) that claim is
backed by a documented, testable contract rather than just a clean `grep`. Any indexer,
including a push/API one that can't glob a directory, has two rules to follow — stated in full
in the repo README's **"Using a different indexer"** section, summarized here:

1. **Index `output_dir`.** Every digest is a `.md` file under it.
2. **Never index `eventlog_dir`.** It's evidence reached *from* a digest, not a search target,
   and it sits as a sibling of `output_dir` rather than a child specifically so a glob can't
   pick it up by accident.

A pull indexer (qmd's glob) needs nothing else. A **push** indexer gets two more things:

- **`index.jsonl`** — an append-only manifest, one line per digest block written, living next
  to `output_dir` by default (mode `0600`). Each line carries the block's identity
  (`path` relative to `output_dir`, `session_id`, `turn_uuid`), a `sha256` of **the block, not
  the file**, and `provisional` (`""` for a real digest, `"placeholder"`/`"suppressed"` for a
  stand-in — filter on `provisional == ""` for real digests only). Digests aren't write-once,
  so a consumer needs both of these, not just one: **record identity is `(path, turn_uuid)`,
  last line wins**, and **the indexable document is the whole file** — re-ingest the entire
  `path` whenever a line names it, rather than assembling content from block records.
  `scribe index --rebuild` regenerates the manifest from the digests on disk (how a corpus
  predating the manifest gets backfilled); `scribe index --check` re-derives it in memory and
  exits non-zero on any drift, which is what makes the manifest trustworthy rather than just
  present.
- **`[index] on_digest_written`**, an optional argv-list hook run once per digest, after its
  manifest line lands. It gets a fixed, minimal environment (never scribe's own — the
  summarizer's API key has no reason to reach an indexer process) plus any names listed in
  `on_digest_written_env`, a bounded timeout, and a shell string is refused at config load
  rather than risking a command-injection surface built from the digest path. Failures are
  counted and never affect whether the digest itself was written.
- **`[discovery] emit_frontmatter = true`**, optional and off by default: adds `agent`, `date`,
  `source`, `session_ids` as YAML frontmatter on each digest file without moving the per-block
  anchors — the `SessionStart` journal preview (below) reads identically either way.

Nothing about forge's own qmd-based setup changed in this build — every new key defaults to
current behaviour.

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
most recent digests. The repo carries `hooks/session-start.sh` as the reference wrapper, but
forge's live registration calls a separate, root-owned wrapper script instead — matching the
generic shape in the repo README's "Example deployment" table, not the repo's own script
directly. See the note under [Entry points](#entry-points).

This matters because the `SessionStart` injection is the **only** memory push surface confirmed
to reach a CloudCLI agent session — a hook emitting `hookSpecificOutput.additionalContext` is
surfaced to the agent, while the old `memsearch` `user-prompt-submit.sh` hook emitted a bare
`systemMessage` that CloudCLI drops for agent sessions. Ted saw the latter only in his own
terminal, which is how that gap (vikunja#853) went unnoticed; it closed on cutover rather than
being fixed separately, and `memsearch`'s hook set no longer exists to compare against.

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

**Status:** confirmed live on this host — scribe's `SessionStart` hook is registered as a
root-owned wrapper in `~/.claude/settings.json`, alongside the existing
`core-context.md`/`directives.md` hooks. Registration was part 3 of the
`memory-consolidation-2026-09` programme (vikunja#863), which is now closed — the cutover
happened after the backfill so no agent saw an empty injection on cutover day.

## Entry points

CLI only: `python -m scribe {extract|events|journal|qc|qc-survey|cap-survey|deps-drift|run|recover|index}`.

- `python -m scribe.extract <transcript.jsonl>` — run the extractor standalone.
- `python -m scribe events <session-id> [--path]` — print or locate a persisted event log.
  Exit 1 "none kept" is distinct from exit 2 "could not look."
- `python -m scribe journal` — emit the `SessionStart` hook payload for the calling agent. In
  production this is called by a root-owned deployment wrapper (matching the generic shape in
  the repo README's "Example deployment" table) — **not** the repo's own
  `hooks/session-start.sh` directly. A live git checkout under an agent's write root running on
  every session start was flagged MEDIUM in the part 3 cutover audit; the wrapper is
  deliberately self-contained and published via `forge-scripts-deploy.sh` instead of calling
  back into the repo copy.
- `python -m scribe qc --digest D --events E` — the groundedness gate; exits non-zero on an
  ungrounded digest. See [Session dating and the QC gate](#session-dating-and-the-qc-gate) —
  **still not recommended for per-block cron gating** even after v0.5.0's fix.
- `python -m scribe qc-survey` — new in v0.5.0. Grades every block in a digest corpus against
  its own event log and classifies each rejected path claim (`verbatim` / `home-expansion` /
  `composed` / `suffix` / `absent`). Read-only; writes only to stdout or an explicit `--out`.
  `--rule literal` grades under the pre-v0.5.0 rule for a same-commit before/after comparison;
  `--probe` re-derives the segment floors from cross-session controls; `--bucket absent` isolates
  the control set no tolerance reaches.
- `python -m scribe run` — **defaults to a dry run.** Discovers finished sessions, extracts
  and reports, without constructing a provider, reading a credential, or writing a digest.
  **A dry run still writes:** `upsert_observed` records each transcript's size and mtime
  during discovery — that property is deliberate (invariant 8) and is not the same as "writes
  nothing." Before v0.8.1, the dry-run guard sat below two calls that retire a session's state,
  so a plain `scribe run` was advancing `last_offset` and `status` on production state
  (vikunja#902) — fixed by moving the guard above both; a dry run may observe, it must not
  process. `python -m scribe run --live` runs the full shadow pipeline: summarize and write.
- `python -m scribe recover [--apply]` — reopens sessions whose digest was never really
  written. Dry by default; `--apply` stamps the affected blocks and clears the state, then a
  following `python -m scribe run --live` re-summarizes them. See
  [Provisional digests and `scribe recover`](#provisional-digests-and-scribe-recover) below.
- `python -m scribe cap-survey [--json]` — new in v0.7.0. Re-measures the input distribution
  the three bounded digest caps derive from, reading persisted event logs directly. See
  [Bounded caps are derived per session](#bounded-caps-are-derived-per-session-not-hardcoded-v070).
- `python -m scribe deps-drift [--lock PATH] [--json]` — new in v0.8.0. Compares a deployed
  venv against `uv.lock`'s pins. Run from a source checkout pointed at the deployed venv, not
  from the venv itself — see
  [Dependency drift and the deployed venv](#dependency-drift-and-the-deployed-venv-v080).
- `python -m scribe index [--rebuild|--check]` — new in v0.10.0. `--rebuild` regenerates
  `index.jsonl` from the digests on disk; `--check` re-derives it in memory and exits non-zero
  on drift. See
  [the indexer contract](#the-indexer-contract-and-why-qmd-isnt-a-dependency-v0100) above.

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
- **A path claim is grounded when it composes** (v0.5.0, vikunja#876). The gate used to check a
  path either against the derived rollup set (with containment tolerance) or against the event
  log corpus (exact substring only) — so a true claim joining a directory the log names to a
  relative tail the log also names matched neither and graded as a hallucination. That was the
  dominant cause of QC failure. The tolerance in one sentence: *a path claim is grounded when
  the log holds it — literally, or as a directory prefix plus the whole remaining relative
  tail, a one-segment tail only when the two sit within 120 characters (`ADJACENCY_WINDOW`) of
  each other — and an absolute claim is tested again with its leading directories replaced by
  `~`.* Measured over 470 blocks: block failure 39.6% → 21.5%, path findings 880 → 158. All 26
  claims genuinely absent from their own event log still fail — a gate that passes everything
  is not a gate.
- **21.5% is still too high to gate per-block in a cron.** The recommendation on vikunja#876
  (left open) is a corpus-level rate threshold (~30% against the 21.5% baseline) plus an alert
  on growth in the `absent` bucket, not a per-block exit-code check. With paths fixed, ticket
  and identifier claims were the dominant failure driver next (vikunja#888 — 52 of 101 failing
  blocks failed on nothing else) — **mostly fixed in v0.9.0**: `_CMD_RE`'s delimiter
  mis-pairing was fabricating and dropping spans in both directions (measured: 56 fabricated
  claims across 36 blocks, 30 real spans dropped), and a `\bid` word-boundary gap was missing
  31 of 62 true id-conflation findings. Block failure fell from 21.9% to 20.0% over the live
  corpus after the fix; #888 itself is closed, #876's corpus-level-threshold recommendation is
  still open.

**The post-render redaction guard now states a cause, not just a fire (vikunja#856).** A fire
used to be reported as proof extraction had missed something and told the reader to
investigate `redact.py` — it could not know that from a single fire. It now consults the
persisted event log and classifies each fire as `extraction-miss` / `model-output` /
`undetermined`. "There is no log" supports neither cause; treat `undetermined` accordingly
rather than assuming the worse (or better) reading.

## Run totals, `placeholder`, and `discarded`

A run's totals satisfy `written == summarized + suppressed + placeholder`, and `discarded` is
a fourth, independent counter — added in v0.2.0 — for a digest the model produced and then was
not written (the turn already held a final block). It should be unreachable, and
`python -m scribe run` prints a loud line if it ever fires.

**As of v0.2.0, `placeholder` no longer means a lost summary.** A placeholder session is now
`provisional` (see below) and is retried up to `MAX_PROVISIONAL_ATTEMPTS` (3); the run report
points at `scribe recover` for anything that never lands on its own. **`discarded` is the new
home for LOST** — a discarded digest was generated and then refused at write time, and nothing
currently retries it automatically, so a non-zero `discarded` is worth reporting rather than
shrugging off.

The digest schema declares its own per-field limits to the model (`maxItems` plus the limits
stated in the system prompt, generated from the same `_LIST_FIELDS` source so the two cannot
drift apart) rather than enforcing an unstated rule after the fact. `done` was the one field
still exempt from this until v0.2.0 — capped at 40 while the field it derives from,
`rollup.commands`, reaches 187 — and it was the only field ever observed to violate its cap in
production (30 rejections at 41–67 items, `MAX_DONE_ITEMS` now **200**, set against that input
ceiling rather than against written digests, which top out at exactly 40 with nothing above —
an artifact of right-censoring, not evidence of headroom).

**As of v0.4.0, exceeding a cap no longer means the same thing for every field** (vikunja#884).
The rule three separate cap constants had been approximating for three builds without anyone
stating it: **a field whose ceiling is knowable from the event log VALIDATES — `done`,
`tickets`, `artifacts` — because exceeding it is evidence of invention, and rejection is still
correct.** `found`, `decisions` and `open_items` are free prose with nothing bounding them, so
*any* cap on them is an arbitrary cliff — they now **truncate**: the surplus is dropped, the
block carries a visible `_Truncated: N further items dropped at the M-item cap._` line (not a
bullet — `qc.strip_scribe_markers` removes it before grounding, since it is scribe's own prose
and appears in no event log), and the digest is still written. Run totals gained `truncated`
and `truncated_items`. **Do not read a field's written-corpus maximum as proof its cap is
safe** — the cap censors the corpus by construction; `found` read max 33 across 458 blocks
right up until it overflowed at 44.

A schema violation from a bounded field is still not retried; it fails fast rather than
burning three identical high-token calls before landing on a placeholder.

## Bounded caps are derived per session, not hardcoded (v0.7.0)

`done`, `tickets` and `artifacts` are the three fields with a countable input (`bounded=True`);
overflowing them is read as the model inventing entries and rejects the digest non-retryably.
Through v0.6.0 their caps were global constants set above an observed corpus ceiling — correct
when set, but a snapshot that decays silently as the corpus grows, with no signal until a digest
is discarded. `~/.local/share/scribe/digests/research/2026-09-15.md:1433` held exactly that: a
faithful 103-item `tickets` response rejected against a cap of 100 set when the observed ceiling
was 76.

As of v0.7.0, `schema.caps_for(log)` reads each field's bound from **that session's own
persisted event log** — known before the model call, so it cannot go stale:

| field | denominator | why |
|---|---|---|
| `done` | `stats.tool_events` | `rollup.commands` (the field it replaced) undercounted 45% of 479 measured blocks, by up to 51x — this fleet's work is mostly not bash |
| `tickets` | `rollup.tickets` | max ratio 5x, only at a rollup of 1 |
| `artifacts` | `files_written` ∪ `prs` ∪ `git_refs` | max ratio 42x — needs the most headroom; the prompt also asks for "services" changed, which has no rollup source at all |

The derived cap is `max(ceil(denominator * HEADROOM), FLOOR)`, clamped to `floor *
MAX_DERIVED_MULTIPLE` (10x, a deliberately unmeasured containment bound — see the security note
below). The global constants survive as the `FLOOR` and as the fallback for a log with no
rollup, so the cap only ever moves **up**: no session that would have been accepted before this
change can be rejected after it.

`python -m scribe cap-survey` (and `--json`) re-measures the input distribution these caps
derive from, reading persisted event logs directly rather than re-extracting transcripts — the
documented way to re-check the constants, and it works for sessions whose transcripts have
aged out at 30 days.

**Security note:** the derived cap's denominator comes from the session's own event log, so
without the 10x clamp an actor able to write under the event-log directory could inflate
`stats.tool_events` and remove the `bounded` class's invention guard for that session outright.
Defence in depth, not a live hole — the same actor already holds a strictly worse primitive in
editing the log's turn content directly, which the summarizer treats as ground truth.

**Truncation is now visible.** `truncated`/`truncated_items` (the unbounded prose fields —
`found`, `decisions`, `open_items` — which drop the surplus rather than rejecting) have been
aggregated correctly since v0.5.0 but printed nowhere except under `--json`, which the cron does
not pass — the counter existed and was invisible. `scribe run`'s plain output now prints a
truncation line with a per-field breakdown (`truncated_fields`) when it fires, and a
`full_read` flag distinguishes a recovery re-read (input-bounded, a whole transcript) from an
ordinary incremental sweep (a growing one) — pooling the two obscured which one was actually
truncating.

## Dependency drift and the deployed venv (v0.8.0)

`python -m scribe deps-drift` (and `--json`) compares a deployed venv against `uv.lock`'s pins.
It exists because the tree CI audits is not the tree forge runs: `venv-deploy.sh` builds a wheel
and pip-installs it, re-resolving from `pyproject.toml`'s bounded ranges at deploy time, and
nothing on forge reads the lock. A green dependency audit in CI is therefore a statement about a
resolution the host may never have installed.

**This is a source-checkout tool, not something run from the deployed venv itself.** It needs
`uv.lock`, which an installed wheel does not carry — run it from a checkout of the repo,
pointed at the deployed venv, not from `/opt/venvs/scribe` directly. It always reports and never
fails; drift here is expected (`venv-deploy.sh` never reads the lock) and is not a fault.

CI gained a dependency audit in v0.8.0 that did not exist before: `uv lock --check` for
currency, then two `pip-audit --strict --locked` gates, split by runtime and dev directories so
a production-affecting advisory is distinguishable from a dev-tooling one. A release workflow
also exists now — it does not generate release notes; a human authors the release and pushes
the tag, and the workflow attaches verified build artefacts. `httpx` moved from a bare
`>=0.27` floor to `>=0.27,<0.29`, since a bare floor is what let a sibling repo silently resolve
two majors past anything tested.

## Provisional digests and `scribe recover`

v0.2.0 replaced two dead ends a lost digest used to fall into — a suppression read as
`summarized` (terminal), a schema rejection read as `failed` but left `last_offset` behind, so
the byte-based scan kept re-offering it (one session reached 12 paid summarization calls and
could never land, because `append_block` refused the result every time) — with a single
retryable state:

- **Session status.** A fifth status, `provisional`, in
  `~/.local/state/scribe/scribe.sqlite3`, alongside `active`/`complete`/`summarized`/`failed`.
  It means "written, but not with a digest," and is retried a bounded three times
  (`MAX_PROVISIONAL_ATTEMPTS`).
- **Anchor attribute.** A digest block's anchor comment can now carry
  `provisional:placeholder` or `provisional:suppressed`. **No attribute still means a finished
  digest** — every block written before v0.2.0 reads that way, so nothing needed migrating. A
  provisional block is replaced in place by the first real digest for that turn; a final block
  is never overwritten.
- **`scribe recover [--apply]`** joins on `transcript_path`, not `session_id`. `session_id` was
  empty on every row before v0.2.0 (`scan` upserts from a filesystem stat; the session id lives
  inside the transcript) and is now populated on every row — the join key did not change, since
  the two are equivalent only where the basename convention holds.
- **A stand-in superseded by a later real block is ignored, not counted as loss** (v0.4.1,
  vikunja#886). A session can leave a stand-in on more than one turn while only the last turn's
  is ever reachable; the earlier one used to read as recoverable loss forever, which paged the
  daily detector every morning for something no action could fix.

### Recovery is not transcript-bound

As of v0.3.0, a missing transcript is no longer the end of the line. `eventlog.load_eventlog()`
can rebuild an `EventLog` from its persisted JSON copy, and `pipeline.process_session` falls
back to it whenever the transcript file is absent (`OSError` from a genuine read failure is
**not** treated as "transcript absent" — only a file that plainly does not exist takes the
replay path, so a permissions bug can't hide behind a stale-but-plausible reconstruction).
`SessionResult.replayed` is `True` whenever this happened, so a run report shows which digests
are reconstructions rather than direct reads.

This matters because transcripts age out — `cleanupPeriodDays` is now **60**
(`~/.claude/settings.json`, raised from Claude Code's unconfigured 30-day default by part 5 of
`memory-consolidation-2026-09`, vikunja#778) — while `~/.local/share/scribe/eventlogs/` has no
cleanup policy at all. The event log is the durable copy.

**Replay only fires for a session actively being (re)processed, and normally only `scribe
recover --apply` puts an already-summarized session back in that state.** A session that has
never been summarized still has its live transcript in the ordinary case; it's specifically an
*old, finished* digest that recover reopens whose transcript may since be gone. This is the
useful half of "opt-in": as of this doc, 15 of 463 sessions on forge have no transcript on disk,
and most already hold real digests written while the transcript still existed — replaying those
un-prompted would overwrite a good digest with a reconstruction for no reason. `recover` only
touches a session when its digest is actually missing or provisional.

### Exit codes are an interface, not an implementation detail

A scheduled detector (`scribe-recover-check.sh`, part 5 of `memory-consolidation-2026-09`,
vikunja#875) is wired to these, so `0`–`3` cannot be renumbered — only added to. v0.4.0 added
`4` and `5`:

| exit | meaning |
|---|---|
| 0 | nothing lost, or `--apply` completed |
| 1 | unrepaired loss, recoverable |
| 2 | `ConfigError` |
| 3 | unrepaired loss that re-running will not fix — needs a human |
| 4 | **the tool FAILED** — it did not assess the corpus, this is not a finding |
| 5 | **state DB newer than this build** — upgrade scribe, do not touch the DB |

Before `4` existed, only `ConfigError` was caught in `main()`; a corrupt state DB or any other
unhandled exception printed a traceback and exited `1` — indistinguishable from a real
"repairable digest loss" finding, and confirmed live against a scratch corrupt DB. **Poll with
the dry run; `--apply` returns 0 whenever it completes, even leaving unrecoverable blocks
behind** — a cron that repairs and then reports failure on its own success would page every
time it worked.

The state DB is at **schema 2** (`PRAGMA user_version`), and as of v0.4.0 that marker only ever
**advances** (vikunja#877) — it used to be stamped unconditionally on every open, so an older
binary meeting a newer DB silently relabelled the marker downward. Opening a DB newer than the
running binary's `SCHEMA_VERSION` is now refused outright (exit 5 above) rather than silently
corrupting the marker.

**Current production state (verified live, 2026-09-17):** 0 provisional blocks, `scribe
recover` exits 0. The two sessions vikunja#873 had declared permanently unrecoverable —
deleted transcripts, no digest — are **no longer stuck**: part 5 of `memory-consolidation-2026-09`
found both transcripts intact in 30 consecutive daily Backrest/restic snapshots (a gap in
*checking the backup*, not in the data) and restored them byte-exact, after which the ordinary
recover/summarize path produced real digests. #873 is closed. Seeing a residual `provisional:`
marker in an old digest file (e.g. a stale anchor predating a later real block for the same
transcript) is expected and is what "superseded, not counted as loss" (above) describes — check
`scribe recover`'s own exit code and block count before treating a grep hit as a live fault.

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
the retired `memsearch-summarize` exported over HTTP, not gRPC, so a dashboard built against
its spans may not read scribe's cleanly.

## The backfill and where the corpus stands now

The initial backfill (2026-09-15) discovered 436 sessions and wrote 174 digests across 9 agent
directories (developer, doc-health, memory-sync, research, security, steward, sysadmin,
writer, plus `unknown` for unresolvable attribution), with 439 event logs persisted. ~96%
complete at the time — vikunja#868 (contamination guard false-positiving on any
angle-bracketed word) and #872 (the `done` cap) together left 22 of those sessions with no
usable digest. Both fixed in `scribe-digest-loss-2026-09` (v0.2.0), 20 of 22 recovered
immediately; the remaining 2 (vikunja#873) were recovered later, from backup, by part 5 of
`memory-consolidation-2026-09` — see [Recovery is not transcript-bound](#recovery-is-not-transcript-bound)
above. #873 is closed.

Verified live 2026-09-17: 463 sessions tracked, 185 digest files on disk, 0 provisional blocks.
The corpus has kept growing on the hourly cron since the backfill; treat any specific count in
this doc as a snapshot, not a current total — re-derive from `scribe recover`'s dry-run output
or the digest directory rather than trusting a number here.

## Dependencies

- A configured LLM provider for the session-digest stage — `mistral-small-latest` by default,
  or [ollama-queue-proxy](../ai-search/ollama-queue-proxy.md) at `127.0.0.1:11435` if
  configured to use Ollama. Daily roll-up uses `claude -p` (no API key). As of v0.11.0
  (`scribe-public-readiness-2026-09`, vikunja#961), that subprocess runs with a named
  environment (`src/scribe/childenv.py`) — an enumerated allowlist, not the sweep's full
  environment, so a session's roll-up call can no longer see credentials for providers it
  doesn't use.
- `~/.claude/projects/*/*.jsonl` transcripts — read-only, and no longer the *only* source (see
  [Recovery is not transcript-bound](#recovery-is-not-transcript-bound)).
- qmd (`session-digests` collection) for digest retrieval; `qmd-refresh.sh` (hourly cron) for
  keeping it current.
- A root-owned `SessionStart` hook wrapper — matching the generic shape in the repo README's
  "Example deployment" table, not the repo's own script directly; see the note under
  [Entry points](#entry-points).

**Do not copy the provider claims from [memory-architecture.md](memory-architecture.md) or
[memsearch-summarize.md](memsearch-summarize.md).** Both were wrong about the LLM provider
(vikunja#402); see those pages' own corrections. If this page needs to restate the provider,
derive it from `scribe.example.toml` in the repo.

## Related tickets

- vikunja#843 — the original defect this component fixes. Closed on cutover.
- vikunja#845 — repo-conform B14 regex gap, filed during the build, unrelated to scribe's
  function.
- vikunja#846 — `memsearch-spend.sh` reads a log nothing writes, so forge's Mistral spend has
  been under-reported by roughly half. Worth a cross-reference from memory-pipeline cost
  documentation.
- vikunja#850, #856 — closed by the release-readiness build.
- vikunja#853 — SessionStart vs UserPromptSubmit injection asymmetry; closed on cutover.
- vikunja#863 — retirement/cutover build (memsearch removal, scribe hook registration).
  **Closed 2026-09-17** — see the top of this page.
- vikunja#865 — SigNoz dashboard continuity across the gRPC/HTTP exporter change, unconfirmed.
- vikunja#868, #872 — the two causes of ~5% of the backfill losing its digest; closed by
  `scribe-digest-loss-2026-09` (v0.2.0).
- vikunja#873 — 2 sessions declared permanently unrecoverable; **closed** — both restored from
  Backrest/restic backup by part 5 of `memory-consolidation-2026-09`.
- vikunja#877, #880, #884, #886 — schema marker only-advances, `recover` exit codes 4/5,
  truncate-don't-discard, superseded-stand-in fix; closed by `scribe-schema-and-exit-contracts-2026-09`
  (v0.4.0) and the v0.4.1 patch. See [Exit codes are an interface](#exit-codes-are-an-interface-not-an-implementation-detail)
  and [Run totals](#run-totals-placeholder-and-discarded) above.
- vikunja#876 — path-composition groundedness tolerance; **left open** even after the v0.5.0
  fix (39.6% → 21.5% block failure) — the gate still isn't recommended for per-block cron
  gating. See [Session dating and the QC gate](#session-dating-and-the-qc-gate).
- vikunja#888 — ticket/identifier claims were the dominant QC failure driver post-v0.5.0;
  **closed by v0.9.0** (`_CMD_RE` delimiter mis-pairing fix, `_ID_CONTEXT` word-boundary fix).
- vikunja#889 — deferred Low from the v0.5.0 audit (unbounded substring scan in the path
  composition check; not attacker-reachable); **closed by v0.9.0** (`ADJACENCY_SCAN_CAP`, a
  length cap chosen to be verdict-neutral on the measured corpus and controls).
- vikunja#896, #892, #893, #890 — repo-index `deployed: true` correction, README truth pass,
  `isCompactSummary` guard, exit-code comment fix; closed by `scribe-truth-pass-2026-09`
  (v0.6.0). See [Compaction boundaries are not user text](#compaction-boundaries-are-not-user-text-v060).
- vikunja#897 — `stateful` attribute gates zero conformance requirements; filed during the
  truth-pass build, left open.
- vikunja#901, #887 — bounded caps overtaken by the corpus, truncation counter aggregated but
  never printed; closed by `scribe-schema-cap-derivation-2026-09` (v0.7.0). See
  [Bounded caps are derived per session](#bounded-caps-are-derived-per-session-not-hardcoded-v070).
- vikunja#902 — `scribe run` without `--live` was not actually inert against the production
  state DB (`store.mark_summarized` ran before the dry-run guard); filed during the
  cap-derivation build, pre-existing; **closed by v0.8.1** (guard moved above both calls).
- vikunja#903 — `run_cli.py` recommended a nonexistent `scribe recover --status` flag; found
  in the same verification pass; **closed by v0.8.1** (advice corrected, and
  `test_advice_strings.py` added so every printed command is checked against the real parser).
- vikunja#904 — CI gained no dependency audit despite declaring `deployed: true, stateful:
  true`; closed by `scribe-ships-conformance-2026-09` (v0.8.0). See
  [Dependency drift and the deployed venv](#dependency-drift-and-the-deployed-venv-v080).
- vikunja#891 (folds in #899) — the indexer-agnosticism contract for push indexers; closed by
  `scribe-indexer-portability-2026-09` (v0.10.0). See
  [the indexer contract](#the-indexer-contract-and-why-qmd-isnt-a-dependency-v0100) above.
- vikunja#962 — `coderabbit-review-assert` misreads an incremental "files skipped as similar"
  review as stale; filed during the indexer-portability build, still open. Reproduced a second
  time on the public-readiness build's PR (#967, below).
- vikunja#963 — public-readiness tracker; **open** until Ted flips the repo's visibility and
  PR-B (CodeQL + Scorecard) merges.
- vikunja#961 — `claude -p`'s subprocess inherited the sweep's full environment; closed by
  `scribe-public-readiness-2026-09` (v0.11.0). See the `childenv` note under
  [Dependencies](#dependencies).
- vikunja#964 — a setuptools licence-metadata deprecation with a 2027-02-18 removal date;
  closed by v0.11.0 (SPDX `license` string).
- vikunja#952 — the README's deploy section carried a version row that went stale every
  release; closed by v0.11.0 (dropped, replaced with the generic "Example deployment" table).
- vikunja#954 — event-log retention decided (keep indefinitely); closed by v0.11.0. See
  [Three tiers](#three-tiers-and-how-to-get-between-them) above and `AGENTS.md` invariant 18.
- vikunja#965 — event-log growth alert for `scribe-recover-check.sh`; filed for sysadmin during
  the public-readiness build, not yet built.
- vikunja#966, #968 — filed during the public-readiness build; see that build's report for
  detail.
- vikunja#967 — `coderabbit-review-assert` reproducing the same stale-review misread as #962,
  on a different PR the same day.

## Related Docs

- [memsearch-summarize.md](memsearch-summarize.md) — the retired component scribe replaced
- [memsearch.md](memsearch.md) — the retired `UserPromptSubmit` injection hook
- [memory-architecture.md](memory-architecture.md) — full system overview
- Repo README: `~/repos/personal/scribe/README.md`
- Phase docs: `host-forge-knowledge-base/phases/scribe-*.md` (sequence runs from
  `scribe-2026-09.md` through `scribe-public-readiness-2026-09.md` (v0.11.0, latest), by way of
  `scribe-indexer-portability-2026-09.md` (v0.10.0) — v0.8.1 was a same-day patch release with
  no dedicated phase doc, documented only in the repo's own `CHANGELOG.md`) and
  `memory-consolidation-2026-09-p3-memsearch-retirement.md` /
  `memory-consolidation-2026-09-p5-transcript-restore-and-detection.md` for the cutover and
  backup-restore context
