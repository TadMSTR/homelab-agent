# programme-graph

**Last updated: 2026-11-23 (programme-graph-2026-11 p2)**

One graph over every programme ledger, the task queue and the component registry. A
programme is a multi-part build tracked in its own `LEDGER.md`. Before this, each ledger could
only express dependencies on its own parts: the `Depends on` column took same-ledger part numbers,
and the ledger parser rejected anything else. With more than twenty programmes in progress at
once, the links between them lived in ledger prose that no gate could read. Whether a part was
blocked by work in another programme came down to the agent remembering to check.

`programme-graph.py` fixes that in two halves. Ledgers now declare cross-programme
relationships in a form the parser validates, and the graph reads every ledger together and
answers "is this part ready?", "what does finishing this part unblock?" and "which live
programme owns this ticket?". The skills that queue, start, finalize and ticket work call it
before they act.

It shipped in two parts of the `programme-graph-2026-11` programme (vikunja#1587), both on
2026-11-22: the ledger syntax, the graph and the nightly check in part 1, and the skill gates in
part 2.

**Design rule:** relationships are declared by hand; status is derived. The graph never infers a
dependency. The only things it infers are overlap signals (a shared repo, ticket or system), and
it labels those as derived.

## Declaring cross-programme relationships

The ledger parser (`programme-ledger.py`) validates both forms. The graph imports that parser
and never re-parses a ledger itself.

### `Depends on` cells

A cell in a ledger's Parts table can name:

| Form | Meaning |
|---|---|
| `3` | A part of this programme (unchanged) |
| `<programme>#<N>` | Part N of another programme, live or archived |
| `<plan-dir>` | A single-plan directory (a `handoff.md` and no `LEDGER.md`) |

Directory names follow a strict grammar. A missing target, a missing part, a reference to itself
or a malformed cell marks the ledger degraded. So does a reference into a malformed ledger: the
referring ledger degrades too. The parser's cycle detection is still per ledger. The graph is
what finds a cycle that crosses ledgers.

### The `## Cross-programme` table

Relations that aren't dependencies go in an optional table:

```markdown
## Cross-programme

| Part | Relation | Target | Why |
|---|---|---|---|
| 2 | conflicts-with | other-programme#4 | Both rewrite the same skill step |
```

- `Part` is a local part number or `*` for the whole programme.
- `Relation` is a closed vocabulary: `conflicts-with`, `supersedes`, `absorbs`, `related`. A
  `depends-on` row is refused, with a message saying it belongs in the Parts table.
- The heading must match exactly and sit outside a fenced block. A second section degrades the
  ledger.

### `**Repos:**` lines

A part plan can carry a `**Repos:**` line listing the repos it touches, which drives the
`shares-repo` overlap signal. HTML comments on the line are allowed. A plan without the line is
reported as `unknown-repos`, never as "no overlap".

`programme-ledger.py --emit --json` prints every ledger as one read-only JSON document (schema 1),
with each part's `depends_on` split into `local`, `cross` and `plans`.

## What the graph holds

- **Nodes:** programmes, parts, and plans (only the plan directories something references).
- **Declared edges:** `depends-on`, plus the four Cross-programme relations.
- **Derived edges:** `shares-repo`, `shares-ticket` and `shares-system`, only between live parts
  of different programmes.

From those it reports:

| List | What |
|---|---|
| `ready` | Parts whose dependencies are all satisfied |
| `blocked` | Parts with an open dependency, with the ref that blocks them |
| `stalled` | Programmes that need attention, including any that need an operator decision (a failed or cancelled part of their own, or a failed or cancelled outside dependency) |
| `waiting` | Programmes blocked *only* by open cross-programme or plan refs that can still complete. Never also in `stalled` |
| `cycles` | Dependency cycles, including across ledgers |
| `handoff_drift` | Plans whose handoff state disagrees with the queue. A candidate for someone to confirm, never written back |
| `no_task` | Non-terminal handoffs that no queue task names |
| `violations` | Ledger errors |

A `failed` or `cancelled` dependency counts as open, not satisfied.

## Usage

```bash
programme-graph.py --json                          # whole graph, schema 1
programme-graph.py --for <programme>               # one programme's edges, blocks and overlaps (text)
programme-graph.py --ready <programme>#<N>         # is this part ready? (text; exit code is the answer)
programme-graph.py --unblocked-by <programme>#<N>  # what finishing this part makes ready (JSON)
programme-graph.py --ticket <ticket>               # which programmes own a ticket (JSON)
programme-graph.py --check [--digest] [--write-md <path>]
```

- `--ready`, `--unblocked-by` and `--ticket` read the full task queue, as `--json` does. An
  earlier fast path that read single queue files by name was removed, so `--ready` agrees with
  `--json` by construction. A full read takes about 4.4 s for roughly 2,900 queue records.
- `--unblocked-by` lists every not-yet-queued part of another live, in-progress programme that
  names the target and has no other open dependency. It answers whether the target is still open
  or already `completed`, and reports the target's state in `target_status`. A `failed` or
  `cancelled` target unblocks nothing, so the list is empty.
- `--ticket` takes a task id or a full ticket reference; a bare `#N` is a usage error. Each
  owner row carries a role: `tracker`, `part:<N>`, `carry-forward` or `mention`. A ticket is
  owned only by a live `tracker` or `part:<N>` row; `carry-forward` and `mention` are noted,
  never owners.
- `--json`, `--unblocked-by` and `--ticket` output is a documented JSON contract (schema 1),
  pinned by the scripts repo's test suite. Its consumers include the operator panel. Fields that
  hold agent-written `why` text must be rendered inert.

## Outputs

- **`graph.md`**, written by `--write-md` to
  `~/.claude/comms/artifacts/programme-graph/graph.md`: one section per live programme, then the
  stalled list and a `## Waiting programmes` section. The write is atomic, refuses links and
  leaves the file mode 0640; every field is escaped for Markdown tables. It is indexed as its own
  qmd collection, `programme-graph`, marked as generated and not authoritative, and excluded
  from the general artifacts collection. The research agent searches it.
- **The digest**, sent by `--digest`: one Matrix message to the research room listing ready-now
  parts, newly stalled programmes, violations and new handoff drift. It posts only when
  something has changed, and sends the full list on Mondays. `waiting` entries are announced
  when they are new or change, not re-listed weekly. `stalled` is re-listed every Monday, so a
  programme that needs a decision doesn't go quiet. Digest state lives in
  `~/.local/state/programme-graph/digest.json`. The digest goes to research, not alerts: it
  drives planning, not paging.

## Schedule and exit codes

A user crontab entry, not a PM2 process, run daily at `50 6 * * *` (after the build-plan
archiver at 06:45) through the `hc-run.sh` Healthchecks wrapper:

```bash
~/scripts/hc-run.sh --ok 0,1 programme-graph -- python3 ~/scripts/programme-graph.py \
  --check --digest --write-md ~/.claude/comms/artifacts/programme-graph/graph.md
```

It takes about 5 s. Logs go to `~/.pm2/logs/programme-graph-{out,error}.log`.

| Code | Meaning |
|---|---|
| 0 | Clean |
| 1 | Violations or a cross-ledger cycle. A finding, reported in the digest; Healthchecks stays green |
| 2 | Usage error |
| 3 | Degraded: a ledger, queue record, plan or the registry couldn't be read; or the digest has failed to send 3 times running |

`--ok 0,1` means Healthchecks goes red only on exit 3 or a missed run. That is why every
unexpected exception inside `main()` exits 3: an uncaught crash used to exit Python's default
1, which the wrapper accepted as green. `--check` prints its report before writing `graph.md`,
so a failed write doesn't hide it.

The digest has the same rule. A failed send leaves the state alone, and consecutive failures are
counted in `digest.json.failures`. The third is exit 3, and every run stays exit 3 until a send
succeeds. A quiet night with nothing to post doesn't reset the count. A send script that isn't
executable is exit 3 straight away.

## Skills that gate on it

Nine existing skills call it; there is no separate skill to remember. Skills read JSON only from
the JSON modes. For `--ready` and `--for` they act on the exit code and quote the text, never
parse it. Exit 3 is always a stop that names the error.

| Skill step | Mode | What it does |
|---|---|---|
| `shared-build-review` Step 0b, `research-plan-queue` 2b | `--ready` | Replaces the old hand read of the `Depends on` cell. Exit 0 continue; exit 1 stop and quote the output (it names each open local, cross or plan ref); exit 3 stop. A `failed` or `cancelled` dependency still needs the operator |
| `research-plan-preflight` (before queueing part N>1), `research-plan-create` | `--for` | Copies every declared edge, every blocked part with its open ref and every `shares-ticket` overlap into the ledger's Carry-forward, in both ledgers when it bears on the other programme. A `shares-repo` overlap is recorded only after reading the other plan and finding a shared file or deploy target |
| `shared-build-finalize` Step 8, `research-task-queue` Step 3 | `--unblocked-by` | After the next-part hand-back, one research task per `would_become_ready` entry in another programme, skipping any part an open research task already names. Runs on the last part too. The finalize summary gains a `Cross-programme: <N> hand-backs` line |
| `ticket-batch-select` Step 3, `ticket-brief` Step 1, `ticket-verify-sweep` Step 8 | `--ticket` | A ticket with a live owner is left out of a batch unless the batch is for that programme, written into the brief, and moved to "close at finalize" in the sweep |

Hand-backs carry only structured fields (a validated ref, a guarded part name, a ledger path),
and research re-gates with `--ready` before anything is queued. A crafted ledger can't get a
blocked part queued.

## Operations

```bash
# Full check by hand, without posting to Matrix or rewriting graph.md
python3 ~/scripts/programme-graph.py --check; echo "exit $?"

# Is a part ready? What does finishing one unblock?
python3 ~/scripts/programme-graph.py --ready <programme>#<N>
python3 ~/scripts/programme-graph.py --unblocked-by <programme>#<N>

# Logs from the last cron run
tail -30 ~/.pm2/logs/programme-graph-out.log
tail -30 ~/.pm2/logs/programme-graph-error.log

# Generated graph
head -40 ~/.claude/comms/artifacts/programme-graph/graph.md
```

- **Healthcheck:** check `programme-graph` (`50 6 * * *`, 15 min grace). Red means exit 3 or no
  run, never just findings.
- **Digest stuck red:** after 3 failed sends every run exits 3. Once the send path is fixed,
  delete `~/.local/state/programme-graph/digest.json.failures`.
- **New qmd collection:** qmd indexes a new collection only on `qmd update` (the hourly refresh),
  not on restart, so the collection appears once `graph.md` exists and a refresh has run.

## Limitations

- **`--ready` is a skill step, not a queue gate.** Nothing in the task queue itself enforces
  `Depends on` (vikunja#527).
- **Handoff drift is a candidate list.** A matched task can cover only part of a plan, so each
  entry needs a person or research to confirm it. There is no suppression list for reviewed drift
  yet (vikunja#1590).
- **`shares-repo` is coarse.** Most repo-level overlaps come from the two busiest repos (stacks
  and scripts), which is why skills don't copy them wholesale.
- **`**Repos:**` parsing is cautious.** A line over 500 characters isn't parsed, and a stray `<!--`
  with no `-->` in the same paragraph makes the line unknown rather than a shorter list. Many part
  plans still have no `**Repos:**` line at all and show as `unknown-repos`.
- **Import-time errors aren't covered** by the exit-3 catch-all, which only wraps `main()`.
- **It runs from the agent-writable scripts checkout**, an accepted risk recorded alongside
  kb-lint's.
- Remaining audit what-ifs are deferred (vikunja#1589). Part 3, still open, is to have the
  archiver's guard read inbound `depends-on` edges from `--json`.

## Related docs

- [forge-deploy](forge-deploy.md): how both parts were deployed
- [doc-health](doc-health.md): kb-lint, which uses the same 0 / 1 / 3 exit convention
- [healthchecks](../observability/healthchecks.md): cron liveness for the nightly check
- [task-queue-mcp](../agent/task-queue-mcp.md): the queue the graph reads
