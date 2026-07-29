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

`/opt/venvs` is `ted`-owned and `ted`-writable. Any agent holding `system-ops` shell access can
modify a non-editable venv's installed package exactly as easily as an editable source tree —
this script does not close that path and was never intended to. What it buys is auditability
and accident-resistance: a deployed artifact that can state its own version and provenance,
and a build that fails safely instead of shipping a silently-broken wheel. Do not cite it as a
mitigation for agent-writable code paths.

## Registered services

| Service | Venv | PM2 process(es) |
|---------|------|------------------|
| `memory-metadata-mcp` | `/opt/venvs/memory-metadata-mcp` | `memory-metadata-mcp` |
| `memsearch-mcp` | `/opt/venvs/memsearch` | `memsearch-mcp` |
| `memory-fulltext-mcp` | `/opt/venvs/memory-fulltext-mcp` | `memory-fulltext-mcp` |
| `githost-mcp` | `/opt/venvs/githost-mcp` | `githost-mcp-{developer,sysadmin,security,writer,research,harlock}` |
| `datastore-mcp` | `/opt/venvs/datastore-mcp` | `datastore-mcp` |
| `nextcloud-mcp` | `/opt/venvs/nextcloud-mcp` | `nextcloud-mcp` |
| `scoped-mcp` | `/opt/venvs/scoped-mcp` | `scoped-mcp-{developer,sysadmin,security,writer,research}` |

`scoped-mcp` proxies every agent's own tool access, including the agent running this script —
always deploy it with `--no-restart`, then restart the four non-sysadmin brokers deliberately.
`scoped-mcp-sysadmin` is restarted by the operator, never by the sysadmin agent itself: a
failed self-restart would remove the very channel needed to diagnose and roll back.

`/opt/venvs/memsearch` additionally hosts the `memsearch` Claude Code plugin package, which is
**deliberately editable** (it carries un-versioned forge-local patches a reinstall would
revert) — don't confuse its dist-info with the non-editable `memsearch-mcp` package that
shares the same venv.

Dependency-only venvs with no self-package (`agent-bus`, `doc-sync`, `graphiti-ingest`,
`langfuse-hook`) are out of scope — there is no install mode to standardize.

## Operations

Check drift for one service (safe, read-only, no privileges needed):

```bash
~/scripts/venv-deploy.sh --service memsearch-mcp --check
```

Deploy the highest semver tag on the remote:

```bash
~/scripts/venv-deploy.sh --service githost-mcp
```

Deploy a specific tag and preview only:

```bash
~/scripts/venv-deploy.sh --service nextcloud-mcp --ref v0.2.0 --dry-run
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
