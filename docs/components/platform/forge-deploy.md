# forge-deploy

**Last updated: 2026-11-16 (forge-deploy 0.2.1)**

The one entry point for deploying anything on the host. Before it, each service type had its
own deploy habit: `venv-deploy.sh` for Python venvs, `git pull` plus a PM2 restart for script
trees, `docker compose up` for stacks, a hand-written root script per scoped-mcp release. None
of them asked whether the commit had been reviewed. `forge-deploy` puts one gate in front of
all of them. It refuses a commit that isn't merged, CI that isn't green, a build whose security
audit hasn't cleared and an invocation nobody approved. Only then does it run the service
type's adapter, with a rollback point, a health probe, an automatic rollback on failure and one
event on the agent bus.

It shipped in two parts of the `deploy-standard-2026-11` programme: the core and the first
adapters in 0.1.0 (2026-11-10), and an adapter plus a descriptor for every running service in
0.2.0 (2026-11-13). 0.2.1 is a fix release.

## Usage

```bash
forge-deploy <service> --build NAME --sha SHA|merged [--dry-run] [--json]
forge-deploy <service> --verify --build NAME --sha SHA   # after a needs-operator stop (exit 20)
forge-deploy <service> --no-build "<reason>" --sha SHA   # operator only, at a real terminal
forge-deploy --check [--json] [<service> ...]            # read-only drift report
```

- `--sha` is a full 40-hex commit, or `merged`: the commit that merged the build's PR, found
  from the build's audit-clearance record. A plan can name `merged` before the merge exists.
- `--dry-run` runs every check and prints what apply would do, writing nothing.
- `--check` reports each service's deployed commit as its adapter sees it, against the remote
  default branch. Exit 0 in sync, 1 drift, 3 gap. Other tools (the code-review baseline) read
  its `--json` output as the shared "what is deployed" answer.
- Options can't be abbreviated: `--no x` is a usage error, not `--no-build`.

## Where it sits in a build

A build plan ends with a `## Deploy (after audit)` table, one `forge-deploy` command per row.
The build's agent does the work, the security agent audits it, and the finalize step records
the cleared PR head in a `cleared.json` before merging. Each Deploy row then runs as written.
A row that isn't in the build's approved list is refused (13); so is any commit in the deploy
range that no cleared build covers (12). An agent can't deploy unreviewed code by typing a
different SHA.

## Check order

The first check that fails decides the exit code.

1. **Descriptor.** `services/<service>.yaml` is read at the scripts repo's remote default tip
   (never the working tree) and validated against `services/schema.yaml`.
2. **SHA is on the remote default branch** (10).
3. **CI is green** at the SHA (11; 75 if still pending at the ceiling). GitHub repos are polled;
   for a self-hosted Gitea repo the green result recorded at finalize is used.
4. **Adapter pre-check** (3): a dirty checkout, the wrong branch, a venv built by the wrong tool.
5. **Position.** If the target is already *ahead* of `--sha`, something deployed outside
   forge-deploy. That is a gap, and the target is never reset.
6. **Audit cleared** over every commit the deploy adds (12).
7. **Approved row** (13).
8. **Rollback point** recorded before anything changes (3 if it can't be).
9. **Apply, restart, health probe.** On failure: roll back, restart, probe again.
10. **One event**: `deploy.completed`, `deploy.needs_operator`, `deploy.failed` or
    `deploy.refused`.

After the rollback point, every failure goes through rollback, including unexpected
exceptions. The one exception is a target that someone else moved during the deploy: that is a
gap, and nothing is rolled back, because a rollback would undo commits that were already live.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Deployed, health passed |
| 1 | Apply or health failed; rolled back and healthy again |
| 2 | Usage error |
| 3 | Gap: invalid descriptor, unreadable record, no rollback point, target ahead of `--sha` |
| 4 | Deployed and healthy, but its record could not be written |
| 10 | Refused: SHA not on the remote default branch |
| 11 | Refused: CI failed |
| 12 | Refused: audit not cleared for every commit in the range |
| 13 | Refused: not an approved Deploy row |
| 20 | Needs operator: the exact root command is printed; run it, then `--verify` |
| 21 | Rollback failed; service state unknown |
| 75 | CI still pending at the ceiling. Re-run later; never treated as green |

Each state has its own code. A new state gets a new code, never a reused one.

## Adapters

The descriptor names the adapter. Each one implements check, plan, apply and rollback, and
refuses if its target moves mid-deploy. Rollback points are pruned to a retention count
(default 3).

| Adapter | Deploys | How |
|---|---|---|
| `repo-tree` | A script tree run in place (PM2 services, cron scripts) | Fast-forwards the checkout; compare-and-swap rollback |
| `venv-pip` | A pip-built service venv | Wraps [venv-deploy](../venv-deploy.md); any non-zero exit counts as changed and is rolled back |
| `venv-uv` | A uv-built service | `releases/<sha>` built from the lockfile, probed, then a `current` symlink switch |
| `node-release` | A Node service | Same release-directory pattern as `venv-uv` |
| `compose` | One Docker Compose project | Fast-forwards a deploy-only stacks clone, then `pull`, `build`, `up -d --pull never`. Rollback re-tags each service onto its recorded image id |
| `cron` | The user crontab | Installs the tracked crontab file as the whole table; rollback is the saved table |
| `configs` | Config mirrors under the app-data root | File-level copy with a rollback snapshot |
| `observability` | Monitoring configs (Prometheus, Alloy, Telegraf, Grafana) | Signals each changed container to reload and confirms it; Grafana, which has no provisioning reload, is restarted. File-level rollback point: the TSDB is never copied |
| `root-scripts`, `root-manifests` | Root-owned scripts and agent manifests | Stops at 20 with the `sudo` command for the operator; `--verify` then checks the installed copies byte for byte against `--sha` |
| `root-venv` | Root-owned venvs (the scoped-mcp brokers) | Stops at 20; a root installer builds a hash-pinned venv from the commit's `uv.lock` and keeps 3 previous venvs |

The release-directory adapters (`venv-uv`, `node-release`) never touch the running release
until the new one has passed its probe, so a failed build leaves `current` where it was.

## Service descriptors

Every running service has a descriptor: 61 of them in the scripts repo's `services/`, covering
every compose project, PM2 service, venv, cron table and config mirror. Each records the
adapter, the source repo and checkout, the restart set, the health probe and the docs the
service owns.

`service-descriptor.py --coverage` checks the other direction: every PM2 process, crontab line,
system cron file and running compose project must have a descriptor. It runs daily as a cron job.
An uncovered crontab line is reported by hash, never by its text.

## `--no-build`: the operator's escape hatch

For a deploy with no build behind it (an urgent fix, a revert), the operator can pass
`--no-build "<reason>"`. It skips the audit and approval checks only; SHA, CI, rollback, health
and the event still apply. It requires a real terminal and a typed confirmation, and it refuses
in an agent session. That refusal is mistake-proofing, not a security boundary: an agent that
blanked its environment variables and wrapped the command in a pty could get past it. The
control is the rule that an agent never passes `--no-build`.

## State and events

- Per-service state (rollback point, last deploy, pending operator step) lives under a state
  directory in the deploying user's home (`~/.local/state/forge-deploy/<service>/`).
- Each run writes one agent-bus event file to the comms outbox, so deploys show up in the same
  audit stream as everything else agents do.

## Related docs

- [venv-deploy](../venv-deploy.md): the Python venv installer the `venv-pip` adapter wraps
- [doc-health](doc-health.md): kb-lint, which uses the same 0 / 1 / 3 exit convention as `--check`
