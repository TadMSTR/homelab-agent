# forge-config-mcp (forge)

The closed op vocabulary through which [steward](steward.md) authors every config
proposal. `config_propose`, `config_show`, `config_vocabulary`, `config_effective_diff`,
plus lifecycle tools.

**Version: v0.2.0.** Source is a private repo — link to it as private, not a public GitHub
URL, when cross-referencing from elsewhere.

## The two things that make it interesting

**1. It is not a convenience layer.** steward holds no shell and no file-writing tool of
any kind, so this server is the *whole* of steward's ability to act. Until it was deployed,
steward was inert.

**2. Safety by subtraction.** A change that cannot be expressed as one of the ops cannot be
proposed — not by a persuasive prompt, not by a misread instruction, not by prompt
injection riding in on a task description. Deliberately absent from the vocabulary: adding
a new module, any `workspace_access` edit, any `credentials:` edit, any
`argument_filters`/`response_filters` edit, adding a write root, and anything outside the
config directory. Each omission has a recorded reason in source.

Note the asymmetry, because it's the design in miniature: `add_*` ops are narrow and
heavily constrained; `remove_*` ops are permissive, because removal narrows an agent's
reach rather than widening it. The exceptions are the two removals that *widen* — removing
a deny-glob and removing a module grant — which are refused outright by the applier's
invariants rather than left to reviewer judgment.

## Mandatory effective-permission diff

Every proposal must carry one, and it is rendered **by calling the enforcing resolver
itself**, never by reimplementing the resolution rules. This matters because policy
resolution is all-or-nothing per agent — a change scoped to one agent's manifest entry can
silently move a different agent's whole effective grant. That happened once, on this exact
policy surface, and cost real access invisibly in a YAML diff but obviously in an
effective-permission diff. A second implementation that drifts from the first would be
worse than no diff at all, so the diff is produced by importing the same resolver the
applier itself uses, not a maintained copy of its logic.

## Runs under systemd as steward's own user, not the shared process manager

The proposal store this server writes is mode `0750`, owned by steward's own OS user. The
process manager the other resident-agent services run under executes as the shared agent
user, which has group read on that store but not write. Same reasoning as
[steward's](steward.md) own tool broker.

## Two accepted risks — deliberate, not oversights

- **The effective-diff code imports the enforcing resolver from a venv writable by the
  shared agent user**, so anything able to write as that user can execute code inside this
  service. Deliberate: a pinned copy would reintroduce exactly the drift the design
  forbids — the diff has to be produced by the code that actually enforces, or it describes
  a resolver nobody runs. The fix, if the shell-lockdown project ever closes that gap
  fleet-wide, is to make that venv root-owned — not to vendor the resolver.
- **The countersign artefact is group-writable** so the reviewing agent can write it. "Only
  the reviewing agent can countersign" was never enforced by file mode, and this doc
  shouldn't imply it is — it rests on the audit trail and on the applier's substantive-
  verdict gates instead.

## Also worth knowing

Per-op telemetry spans are **not** emitted yet, even though the OTEL endpoint environment
variable is present and the optional telemetry extra is deliberately not installed. The
service therefore reads as telemetry-enabled while emitting nothing — harmless today (there
is no exporter code path to misfire), but worth knowing so nobody concludes tracing is
live.

## Tools

| Tool | Purpose |
|---|---|
| `config_vocabulary()` | The closed op list, and what is absent and why |
| `config_status()` | Health of the store, clone, deploy key and resolver |
| `config_show(agent, source)` | Read the config surface — deployed or the default branch |
| `config_propose(...)` | **The only tool that writes.** Render, push a branch, write the record |
| `config_attach_pr(id, url)` | Record the PR URL once opened |
| `config_effective_diff(id)` | The stored effective-permission diff |
| `config_list_proposals(status)` | Every proposal, newest first |
| `config_get_proposal(id)` | One proposal, including which artefacts are missing |
| `config_withdraw(id, reason)` | Withdraw. Never deletes — a dropped change is part of the record |

There is no tool that applies, deploys, or merges. That is enforced by test, not only by
convention.

## The invariant mirror

`invariants.py` mirrors a **subset** of the applier's own checks at propose time, purely
for timing — a two-second refusal instead of one that only arrives after a human's
countersign and a merge. The applier stays authoritative; this mirror exists so a doomed
proposal fails fast rather than fails late.

As of v0.2.0, the manifest-protecting invariant is **two requirements with different
scopes**, and the split is load-bearing:

- one requirement applies only to agents that carry an allow-list of writable paths
- a second, separate requirement applies to every agent **except steward**, allow-list or
  not

Merging the two into a single check would make the checker refuse the *current* policy and
block every future proposal — including the one that would fix it. A parity test asserts
the shared constants match the applier byte for byte, so the two copies cannot drift
silently.

The module-grant invariant that governs what steward itself may be given access to is now
an explicit allowlist of permitted modules, checked before the older name-pattern check —
which is retained as defence in depth rather than replaced. Adding a module to steward is
deliberately a two-place change.

**A caveat worth knowing before trusting green CI:** the parity sentinel and the
live-policy test both skip when the deployed applier script and the live policy file are
absent from the environment — which is the case inside CI. A skipped sentinel is not a
passing one; only a run against the real deployed applier on forge proves the two copies
actually agree.

## Configuration

All deployment config is read from the environment at startup — never a caller parameter,
because constraining the op vocabulary is pointless if a caller can redirect where the
result lands.

| Var | Purpose |
|---|---|
| `FORGE_CONFIG_STORE_ROOT` | Where proposal artefacts are written |
| `FORGE_CONFIG_REPO_PATH` | This service's own git clone of the config-scripts repo |
| `FORGE_CONFIG_ETC` | Where the deployed (applied) config is read from, read-only |
| `FORGE_CONFIG_GITHOST_VENV` | The deployed git-proxy venv the effective-diff resolver is imported from |
| `FORGE_CONFIG_DEPLOY_KEY` | Dedicated deploy key, write-scoped to the config-scripts repo only |
| `FORGE_CONFIG_REMOTE` / `_BASE_BRANCH` / `_BRANCH_PREFIX` | Git remote, default branch, and the prefix proposal branches are pushed under |
| `FORGE_CONFIG_GIT_NAME` / `_GIT_EMAIL` | Commit identity used for proposal commits |
| `FORGE_CONFIG_MCP_AUTH_TOKEN` | Bearer token, required for HTTP transport |
| `TRANSPORT` / `HTTP_HOST` / `HTTP_PORT` | Transport mode and bind — refuses a non-loopback bind unless explicitly overridden |
| `LOG_LEVEL` / `LOG_FILE` / `FORGE_CONFIG_AUDIT_DIR` / `OTEL_EXPORTER_OTLP_ENDPOINT` | Optional |

## Deployment

Runs as a **systemd unit under steward's own OS user**, not the shared process manager.
The unit file ships in the source repo; sysadmin installs it.

Prerequisites, provisioned once:

1. A proposal-store directory, `0750`, owned by steward's user and group
2. A dedicated clone of the config-scripts repo, owned by steward's user
3. A deploy key scoped to write-access on that one repo only, mode `0400`
4. The bearer token, in an env file readable only by steward's user
5. A module block in steward's own manifest pointing at this service's port

Install non-editable, from a reviewed tag, using the standard venv-deploy tooling for
forge services.

## Tests

```bash
.venv/bin/pytest          # unit tests + the applier-parity sentinel
.venv/bin/ruff check .
```

A byte-identity round-trip test loads and re-dumps every real manifest untouched and
asserts the result is unchanged. These config files are mostly load-bearing comments, and
that test is what makes any diff this server produces provably just the intended edit.

## Related docs

- [steward.md](steward.md) — the agent this server exists to serve; the design rationale
  for the two-layer safety model (closed vocabulary here, hardcoded invariants in the
  applier) lives there
- [scoped-mcp.md](scoped-mcp.md) — the manifest format this service renders into
