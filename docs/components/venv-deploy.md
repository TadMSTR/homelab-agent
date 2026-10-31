# venv-deploy

The repeatable deploy step for forge's Python services. Before this script, "non-editable"
meant someone ran `pip install .` by hand once, and there was no way to answer "what version
is actually running" — the honest answer was "whatever the working tree was at the last
process restart." `venv-deploy.sh` installs a service into its `/opt/venvs/<name>` venv from
a reviewed, immutable ref and proves the result by reading the installed artifact off disk,
rather than trusting `pip`'s exit code.

## Usage

```bash
~/scripts/venv-deploy.sh --service <name> [--ref <tag|sha>] [--dry-run] [--check]
                          [--no-restart] [--recreate] [--create-registry-entry]
~/scripts/venv-deploy.sh --list
```

| Flag | Purpose |
|------|---------|
| `--service <name>` | Which registered service to deploy. See `--list` for the table. |
| `--ref <tag\|sha>` | Ref to install from. A tag name is resolved against the **remote**; a 40-char sha is used as-is after verifying it is reachable from the remote's default branch. Branch names are rejected — a branch is a moving target. Defaults to the highest semver tag on the remote when omitted. |
| `--check` | Read-only. Reports installed vs. source-HEAD vs. component-registry version, and install mode (editable/non-editable/UNKNOWN). Writes nothing, needs no privileges, exits 1 on drift or an editable install. This is the primitive a registry drift check should consume — not yet wired up. |
| `--dry-run` | Resolve the ref and report what would be installed; writes nothing. |
| `--no-restart` | Install but leave PM2 alone — the caller restarts manually. |
| `--recreate` | `pm2 delete` + `pm2 start` from the repo's `ecosystem.config.js` instead of `pm2 restart`. **Required** whenever the venv path or any other exec-path/env field changed — a plain restart reuses PM2's cached script/interpreter and env, so an exec-path change would silently keep running the old one. |
| `--create-registry-entry` | Create the `host-forge-component-registry` entry if one is missing. Off by default: a missing entry is a real gap that should be noticed, not papered over by auto-creating it every run. |
| `--list` | Print the registered service table (venv, PM2 processes) and exit. |

## What it does

1. **Resolves the ref to an immutable commit id from the remote**, never the working tree and
   never a local ref. A tag is resolved via `git ls-remote --tags` (peeled for annotated tags);
   a bare sha is checked with `git merge-base --is-ancestor` against the remote's default
   branch. Both paths reject a commit that isn't reachable from the reviewed default branch —
   this closes the check/use race a local ref would leave open (a ref can be rewritten between
   verifying it and reading through it; a commit id cannot).
2. **Exports the commit with `git archive`** into a clean `mktemp -d`, so a local working-tree
   edit or untracked file can never leak into the installed artifact.
3. **Builds the wheel and vets its module set against source before touching the venv.** Diffs
   the `.py` files in the exported source tree against the `.py` files actually packaged into
   the wheel. This is not hypothetical: `datastore-mcp`'s `.gitignore` carried a `core.*` rule
   (meant for core dumps) that also matched the real source file `tools/core.py`; git kept the
   already-tracked file, but hatchling honoured the VCS-ignore list with no such exemption and
   silently dropped it from every wheel. An editable install hid this for months because it
   points at the source tree directly — the first real install crash-looped the service. A bad
   build now aborts here, with the venv untouched, instead of leaving a broken install armed
   for the next restart.
4. **Force-reinstalls the payload** (`--force-reinstall --no-deps`). Plain `pip install <dir>`
   no-ops and prints "Requirement already satisfied" whenever the version already matches, so a
   code change shipped without a version bump would otherwise silently not deploy while the
   script reported success.
5. **Proves the result by reading `dist-info` off disk**, not by trusting pip's exit code —
   confirms the installed version matches what the ref declares, confirms no editable `.pth`
   remains (checked via `pip list --editable`, not filename pattern-matching — see below), and
   re-runs the module-completeness check against what actually landed in `site-packages`.
6. **Writes a provenance stamp** at `<venv>/.forge-deploy.json`: `service`, `version`, `ref`,
   `commit`, `deployed_at`, `deployed_by`, `source_repo`. This is the artifact's own answer to
   "what is running." If a venv is later rolled back to editable by hand, `--check` marks any
   surviving stamp **STALE** rather than reporting a commit that isn't actually what's running.
7. **Restarts PM2** (unless `--no-restart`) and updates the `host-forge-component-registry`
   entry (`deployed_version`, `deployed_date`, `last_patched`) — the script does not commit the
   registry change itself.

### Editable-install detection asks pip, not filenames

There is no single spelling of "editable." `setuptools` writes
`__editable__.<pkg>-<ver>.pth`; `hatchling` writes `_editable_impl_<pkg>.pth`. An earlier
version of this script's detection globbed only for the setuptools shape and therefore
reported hatchling-editable services as clean non-editable — the exact failure class this
script exists to prevent. Install-mode detection now calls `pip list --editable --format=json`
and normalizes the package name per PEP 503; the old glob is kept only to clean up leftover
`.pth` debris after an uninstall, in both spellings.

## Not a security control

`/opt/venvs` is `ted`-owned and `ted`-writable (`scoped-mcp`'s venv inside it is the one
root-owned exception). Any agent holding `system-ops` shell access can
modify a non-editable venv's installed package exactly as easily as an editable source tree —
this script does not close that path and was never intended to. What it buys is auditability
and accident-resistance: a deployed artifact that can state its own version and provenance,
and a build that fails safely instead of shipping a silently-broken wheel. Do not cite it as a
mitigation for agent-writable code paths.

## Registered services

| Service | Venv | PM2 process(es) | Extras |
|---------|------|------------------|--------|
| `memory-metadata-mcp` | `/opt/venvs/memory-metadata-mcp` | `memory-metadata-mcp` | — |
| `memory-fulltext-mcp` | `/opt/venvs/memory-fulltext-mcp` | `memory-fulltext-mcp` (stopped and removed from PM2; the row and venv remain until it is retired) | — |
| `githost-mcp` | `/opt/venvs/githost-mcp` | `githost-mcp-{developer,sysadmin,security,writer,research,fleet}` | — |
| `forge-config-mcp` | `/opt/venvs/forge-config-mcp` | none (systemd) | — |
| `task-dispatcher` | `/opt/venvs/task-dispatcher` | none (cron) | — |
| `scribe` | `/opt/venvs/scribe` | none (cron) | `telemetry` |
| `scoped-mcp` | `/opt/venvs/scoped-mcp` | `scoped-mcp-<agent>`, nine brokers | — |
| `loki-mcp` | `/opt/venvs/loki-mcp` | none (stdio child of the scoped-mcp brokers) | — |

`--list` prints the live table; check it rather than this one before a deploy.

**An empty PM2 field means "deploy with `--no-restart`."** `forge-config-mcp` is supervised
by systemd (restart it with `systemctl`). `task-dispatcher` and `scribe` are batch CLIs that
cron runs, so the next tick picks up the new venv. `loki-mcp` is a stdio child of the
scoped-mcp brokers that declare it, so only a broker restart replaces the running copy.

**Extras** are an optional last field of a registration, comma-separated, without brackets
(`telemetry`, not `[telemetry]`). The script installs them with the dependencies, then
verifies that every dependency of each extra is actually installed. *Why:* scribe emits OTel
spans only when its `telemetry` extra is installed and an OTLP endpoint is set. Dropping the
extra doesn't fail a deploy; it produces a clean, successful, silent one.

`datastore-mcp` was registered here until it was parked on 2026-10-25; its registration is now
a comment, and its venv and PM2 process are removed (see
[datastore-mcp.md](mcp-servers/datastore-mcp.md)). `nextcloud-mcp` was registered here until it
was retired on 2026-10-28; its registration, venv and PM2 process are removed (see
[nextcloud-mcp.md](nextcloud-mcp.md)).

**This script no longer deploys `scoped-mcp`.** Its venv is now `root:root`, so an agent
can't write it. Each release ships with a reviewed root deploy script that the operator runs
with `sudo`, which installs the release and restarts all nine brokers, the sysadmin broker
last. The row stays so the table is truthful about what backs the venv, and so the broker
list has something to be checked against (`pm2 jlist` versus the row's PM2 field). Every
agent's tool access, including the agent running a deploy, goes through these brokers, which
is why `scoped-mcp-sysadmin` is restarted by the operator, never by the sysadmin agent itself:
a failed self-restart would remove the very channel needed to diagnose and roll back.

**`memsearch-mcp` is retired** (2026-09-17, see [memsearch-mcp.md](memory/memsearch-mcp.md)) —
removed from the registered-services table above; there is no `memsearch-mcp` PM2 process for
this script to deploy or check anymore. `/opt/venvs/memsearch`, which also hosted the
**deliberately editable** `memsearch` Claude Code plugin package (it carried un-versioned
forge-local patches a reinstall would revert), has since been removed; the plugin was
uninstalled first (see
[forks.md](../operations/forks.md#memsearch--retired-2026-09-17-fork-no-longer-actively-synced)).

### Out of scope

| Venv | Why | How it is built |
|------|-----|-----------------|
| `doc-sync`, `langfuse-hook` | dependency-only: no self-package, so there is no install mode to standardize | by hand; doc-sync's dependency floors are recorded as comments in `venv-deploy.sh`, to reapply on any rebuild |
| `agent-bus` (the repo-local `venv/` in its checkout) | no self-package: PM2 runs `server.py` from the source checkout | from its committed `uv.lock`, by the install script in its README "Installation" section. The old `/opt/venvs/agent-bus` is a dead copy |
| `doc-cache-mcp` | built from its committed `uv.lock`, without pip, so this script's pip-based install can't deploy it | from a fresh clone of the release tag, by the install script in its README "Installation" section |

`agent-bus` (from v0.6.0) still has no self-package, so it stays out of this script's scope,
but not because it has no install mode. Its venv has a lock-based install of its own:

```bash
uv sync --frozen --no-install-project --extra server --python /usr/bin/python3.13
```

The README script wraps that with the source-tree checks a run-from-source service needs: it
removes bytecode and caches, refuses any ignored file outside `venv/` and `.env*`, checks the
tag, and reads the result back with `uv sync --check` against the lock.

`doc-cache-mcp` (from v0.4.0) left this script for a similar reason. Its README script builds
`/opt/venvs/doc-cache-mcp` with `uv sync --frozen --no-editable --extra telemetry` and no pip.
Keep the `telemetry` extra on any rebuild: without it the service's audit-sink metrics go
silent, and silence reads as healthy.

The `graphiti-ingest` and `memsearch` venvs have since been removed from `/opt/venvs`.

## Operations

Check drift for one service (safe, read-only, no privileges needed):

```bash
~/scripts/venv-deploy.sh --service memory-metadata-mcp --check
```

Deploy the highest semver tag on the remote:

```bash
~/scripts/venv-deploy.sh --service githost-mcp
```

Deploy a specific tag and preview only:

```bash
~/scripts/venv-deploy.sh --service memory-metadata-mcp --ref v0.2.0 --dry-run
```

List registered services:

```bash
~/scripts/venv-deploy.sh --list
```

## Dependencies

- `git`, `pip`, `pm2` on `PATH`
- Target venv must already exist with a working `bin/python3`
- `~/repos/gitea/host-forge-component-registry` checkout (registry updates; override with
  `VENV_DEPLOY_REGISTRY`)
- Network access to the service repo's `origin` remote for ref resolution

## Related

- ADR: `design-records/2026-07-28-venv-install-mode-standardization.md`
- Build: `venv-install-standardization-2026-07`
- Script: `host-forge/scripts` → `scripts/venv-deploy.sh`
