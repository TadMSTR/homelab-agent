# dockhand-mcp

FastMCP Python MCP server wrapping the Dockhand REST API. Gives agents structured access to
Docker container, stack, image, volume, network, schedule, and host state, with the ability
to take container and compose stack actions. One codebase runs as two separate instances: a
main instance that can reach every Dockhand environment, and a second instance pinned to one
remote host's environment.

- **Version:** 0.8.0 (2026-10-25) — hardened against Dockhand 1.0.55: 12 new read tools
  (18 → 30), env-dump masking, an acknowledgement flag on every `stack_action`, environment
  pinning (`DOCKHAND_ALLOWED_ENVS`), compact `list_stacks`/`check_updates` output, and a
  uniform error contract. **Four behaviour changes break existing callers** — see
  [Behaviour changes in 0.8.0](#behaviour-changes-in-080).
- **Repo:** `TadMSTR/dockhand-mcp` (public)
- **Transport:** long-lived PM2 HTTP service per instance, fronted by scoped-mcp via `url:`.
  `stdio` remains the local-dev default (`MCP_TRANSPORT` unset).
- **Auth:** `http` mode requires a bearer (`DOCKHAND_MCP_BEARER`, ≥ 16 chars) presented as
  `Authorization: Bearer`; startup fails closed on a non-loopback host, a missing bearer, or
  a too-short one. Dockhand itself is reached with `DOCKHAND_API_TOKEN`.
- **Wrapped service:** [Dockhand](../foundation/dockhand.md), verified against v1.0.55.

## Port / endpoint

| PM2 app | Bind | Environments | Bearer source | Consumer |
|---------|------|--------------|---------------|----------|
| `dockhand-mcp` | `127.0.0.1:8505/mcp` | all; default env `1` (the local host) | `DOCKHAND_MCP_BEARER` | sysadmin agent |
| `dockhand-mcp-fleet` | `127.0.0.1:8510/mcp` | **pinned** to one remote host's environment (`DOCKHAND_ALLOWED_ENVS`) | its own `DOCKHAND_MCP_FLEET_BEARER`, passed in as `DOCKHAND_MCP_BEARER` | fleet agent |

Both apps are defined in the repo's `ecosystem.config.js` and run the same code from the same
venv. The fleet app was added after the 0.8.0 tag and sits under `[Unreleased]` in the
CHANGELOG. It is a deploy-config change, with no new code.

Start one app at a time. A bare `pm2 start ecosystem.config.js` starts or restarts both:

```bash
env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin pm2 start ecosystem.config.js --only dockhand-mcp-fleet
pm2 save
```

Running from a clean `env -i` keeps the interactive shell's exports out of the stored PM2
environment. One process started from an interactive shell picked up every key in the shared
secrets file. It had to be recreated.

Neither port should be exposed beyond loopback.

## Tools

30 tools. All are read-only except `container_action`, `stack_action`, and
`update_container` (the three HITL-gated tools). `validate_stack` is a POST to Dockhand's
lint route and changes nothing.

| Tool | Description |
|------|-------------|
| `get_health` | Dockhand health status and timestamp |
| `list_containers` | All containers: name, image, status, environment |
| `list_stacks` | Compose stacks, **compact by default** (status, health, counts, each container's name/service/state). `detail=true` or `names=[...]` for full rows |
| `list_images` | All images: id, tags, size, created |
| `list_volumes` | All volumes: name, driver, mountpoint, labels |
| `list_networks` | All networks: name, driver, scope, attached containers |
| `get_host_info` | Docker host: hostname, CPU, memory, uptime, container counts |
| `inspect_container` | Full container config, with layered secret redaction (see [Secrets](#secrets-in-inspect_container)) |
| `get_container_logs` | Combined stdout/stderr, `tail` 100 by default; `since`/`until` windows. **Env-file dumps masked** (see [Env-file dumps](#env-file-dumps-in-dockhands-log)) |
| `get_container_stats` | One-shot CPU / memory / network / block-IO snapshot |
| `get_stack_compose` | A stack's compose content and resolved paths; inline secret-shaped values redacted (`redacted_values`) |
| `get_pending_updates` | Containers with an image update from the last check; each row has `checked_age_hours`, and `stale` marks rows over 7 days old |
| `check_updates` | Run an image update check (synchronous, slow). **Returns only rows needing attention** (an update, an error, or a pin not `current`) plus an `attention_summary`; `include_all=true` for every row. Pinned rows carry `pin_assessment` |
| `update_container` | Re-pull and recreate a container in place. Accepts a name, short id, or full id |
| `container_action` | `start`, `stop`, `restart`, `pause`, `unpause`, `remove` |
| `stack_action` | `start`, `stop`, `restart`, `deploy`. **Requires `acknowledge_env_log=true`** (see [Stack actions](#stack-actions)) |
| `scan_image` | Trivy/Grype CVE scan by image name; takes `environment_id` |
| `get_activity` | Dockhand operations log, filterable by container, actions, date range, and environment |
| `get_activity_stats` | Event totals, today's count, counts by action (restart loops show here) |
| `get_stack_stats` | CPU / memory / network / block-IO snapshot per stack |
| `get_disk_usage` | `docker system df` totals and the largest images and volumes |
| `get_vulnerability_summary` | Stored scan totals by severity, plus one filtered page of findings |
| `list_stack_deploys` | A stack's deploy history: when, who, duration, options, summary of changes (no log text) |
| `get_stack_deploy_log` | One deploy run's compose output, env dumps masked |
| `validate_stack` | Lint a stack's compose file (or a proposed edit) with Dockhand's preflight validator; findings redacted |
| `get_version_notes` | Upstream release notes for the versions an update would cross; labelled `content_trust: untrusted` |
| `list_schedules` | Dockhand's schedules (auto-updates, start/stop, git syncs, prune, backups, system jobs) with cron, next run, enabled state |
| `get_schedule_executions` | Schedule run history, newest first; logs masked |
| `get_scheduled_actions` | A container's scheduled start/stop times and where they come from (read only) |
| `get_auto_update_policy` | A container's auto-update setting and the vulnerability criteria that block an update (read only) |

Every tool except `get_health` accepts an optional `environment_id`, as an integer or a
string (`True` is refused rather than read as env 1).

### Excluded routes

Dockhand 1.0.55 exposes 285 routes. These are deliberately not wrapped, and a test fails if
a call to one appears:

- `containers/{id}/exec`, `exec/run`, and every `files/*` route (a shell in, and writes to,
  a container's filesystem); `system/files`
- `stacks/{name}/env`, `stacks/{name}/env/raw`, `git/stacks/{id}/env-files` (unmasked env values)
- Hawser tokens, backups/restore, secret providers, registry credentials
- every schedule, auto-update, scheduled-action, report, or tag **mutation**
- activity and deploy-history DELETEs, prune, and the Server-Sent Events streams

A second test pins the set of tools that POST or DELETE at all. A new mutating tool needs a
HITL line in every manifest that loads this server *before* it is deployed.

## Behaviour changes in 0.8.0

| Change | Before | Now |
|--------|--------|-----|
| `stack_action` acknowledgement | no flag | every action refused without `acknowledge_env_log=true` |
| `stack_action(deploy)` pull default | `pull=True` (`--pull always`) | `pull=False` (plain `compose up -d`) |
| `list_stacks` | full rows (~180k chars for 34 stacks, more than a tool result holds) | compact (~17k chars for 35 stacks) |
| `check_updates` | every row (~55k chars) | attention rows only (~22k chars for 114 containers) |

Also new: `update_container` resolves a name before the POST (an unknown name errors without
spending a HITL approval or a rate-limit slot), and transport errors, timeouts, and non-JSON
200s now return `{"error": ...}` with status 0 instead of raising out of the tool.

**Deploying 0.8.0 needs a reinstall, not a restart.** The package moved to a `src/` layout,
and an editable install records paths. Installs use `uv.lock`.

## Stack Actions

`deploy` sends `{"pull": …, "build": …, "forceRecreate": …}`. The other actions send no body.
Passing any of the three flags to them is an error, not a silent no-op.

```python
stack_action("example-stack", "deploy", acknowledge_env_log=True)             # compose up -d
stack_action("example-stack", "deploy", acknowledge_env_log=True, pull=True)  # --pull always
```

**Why the acknowledgement exists.** Dockhand prints the stack's whole `.env` to its own
stdout on start, stop, restart, and deploy. This was measured on 1.0.55 with a canary
stack. Every secret in that file lands in `docker logs dockhand` and in any log pipeline
that ships that container. Without the flag the call is refused before any request, and the
error names the alternative: run `docker compose` for the stack directly. With the flag, the
choice is visible in the HITL approval prompt's arguments. HITL is the gate, and the flag
records intent.

`pull=False` recreates only services whose resolved config changed, and still pulls a digest
pin that is not present locally. `pull=True` re-resolves every image and can recreate
services you did not intend to touch.

`deploy` is whole-stack. The REST route has no service parameter, and that is an upstream
limitation. **For a single-service deploy, or any stack with secrets in its `.env`, run
`docker compose up -d <service>` directly.**

Stacks whose `env_file` lives outside the directory mounted into Dockhand cannot be deployed
through Dockhand at all.

## Asynchronous Actions

The 1.0.55 spec documents a `jobId` for `start`/`stop` and SSE streams for `restart`/`deploy`.
With this client's `Accept: application/json` header, all four answer `{success,
output|error}` directly (measured live). A `jobId`, if one appears, is polled to completion.
A returned `success: false` is a completed failure, not a queued job.

## Environments and the pinned instance

Every Dockhand endpoint reads the environment from `?env=<int>`, and list endpoints
**silently return an empty array** when it is absent. Tools resolve it as
`explicit environment_id → DOCKHAND_DEFAULT_ENV → clear config error`. Optional-filter routes
(`get_activity`, `get_activity_stats`, `list_schedules`, `get_schedule_executions`,
`scan_image`) treat no `environment_id` as "every environment" on an unpinned instance.

`DOCKHAND_ALLOWED_ENVS` (comma-separated ids) confines an instance:

- A call naming an environment outside the list is refused **before any request**. On the
  fleet instance, that includes the local host's own environment.
- With more than one id listed, `environment_id` is required and no default applies.
- Optional-filter routes are always filtered to the pin, and schedules or executions from
  other environments are dropped.
- A deploy log is read only after its run's environment is checked.

**The pin lives in dockhand-mcp, not Dockhand.** The single Dockhand API token behind both
instances is valid for every environment. The pin is only as strong as the pinned instance's
config and the isolation of its port and bearer. Give the pinned instance its own bearer and
give the confined agent no route to the unpinned instance's port or token.

## Update Workflow

```
1. check_updates()          # contacts a registry per image; can be slow
2. get_pending_updates()    # reads the result back later; check `stale`
3. get_version_notes(id)    # optional — what the update crosses (untrusted text)
4. scan_image(image)        # review CVE count before pulling
5. update_container(id)     # re-pulls and recreates in place
```

`update_container` posts to `POST /api/containers/batch-update`, which does the
inspect/pull/recreate cycle server-side. It does not shell out to `docker compose`. Compose
labels and the config hash survive, so a later `docker compose up -d` reports no change. A
container labelled `dockhand.update=false` comes back as `{"success": true, "skipped": true}`.
Read `skipped` explicitly.

## Digest-Pinned Images: `pin_assessment`

Dockhand resolves `repo@sha256:X` to `X` to check for updates. A bare-digest pin therefore
reads `hasUpdate: false` whether or not its tag has moved. Since 1.0.54 Dockhand does flag
`tag@sha256` pins whose tag has moved (`pinnedToDigest: true, hasUpdate: true`), but it
still reports nothing for bare-digest pins.

The answer comes from a separate scheduled digest-pin checker that writes a JSON report to
disk. This server reads that report and overlays it. It never contacts a registry itself.

- Every row whose image ref contains `@sha256:` gets
  `pin_assessment: {status, detail, report_generated, report_state}`. Floating-tag rows get
  no key.
- Dockhand's own fields pass through unchanged.
- The top level gains a `digest_pins` summary with a `by_status` count.

`status` is the report's status verbatim (`current`, `update`, `exempt`, `exempt-expired`,
`unresolvable`, `error`, `known-stale`, `known-stale-expired`, `drift`, `undeclared`). The
one status this server adds is **`not_assessed`**, which means *unknown*, never *current*.
It is used when the report is `missing`, `unreadable`, `schema_mismatch` (anything but schema
`1`), or `stale` (older than `DIGEST_PIN_MAX_AGE_H`). It is also used per row when a
container is not in the report or runs a different image than the one assessed. A report
problem never fails the tool.

## Secrets in `inspect_container`

Dockhand masks only variables it recognises as a project's registered secrets. Stacks that
supply env via `env_file` paths outside Dockhand's mount have none registered, so their
secrets come back in the clear. This server adds layered redaction:

| Rule | Effect |
|---|---|
| Credential-shaped key (`*PASS*`, `*TOKEN*`, `*SECRET*`, `*_KEY*`, `*AUTH*`, …) | Redacted, unless the value cannot be a secret (flag, number, empty) |
| Any long opaque value | Redacted regardless of key name |
| Credentials in URL values and query strings | Stripped. Userinfo ends at the last `@`, so passwords containing `/`, `@`, `?`, or `#` are caught |

It covers `Config.Env` and `Config.Labels`, **not** `Cmd`, `Entrypoint`, or `Args`. Treat
the output as sensitive regardless.

## Env-file dumps in Dockhand's log

`get_container_logs`, `get_stack_deploy_log`, `get_schedule_executions`, and `stack_action`'s
own `output`/`error` mask what Dockhand prints when it parses a `.env`. This applies to
**every** container, because the mask keys on the text and not the container name:

| Layer | What it catches |
|---|---|
| Block | Everything from `Raw content:` to `Total lines: N` is masked, including continuation lines of multi-line values |
| Fail closed | A cut end masks to the end of the text; a cut start masks the `N` lines before the end marker; an unexpected frame line starts the mask early |
| Skipped-lines summary | Dockhand's `Skipped lines (N): …` summary, which repeats commented-out lines and continuations in clear, is masked whole |
| Env-shaped lines | `KEY=`, `# KEY=`, `export KEY=` (dot and dash keys too) get the value-shape redaction |
| Opaque lines | A line that is nothing but a long opaque token (for example a PEM body line) is masked by shape |

`masked_lines` reports what was removed. **Accepted residual:** if a `since`/`until` window
cuts off both markers, a short, non-opaque continuation line with no key can pass through. A
secret in free text with no `KEY=` before it has nothing to match. Treat log output as
sensitive.

This masks only what dockhand-mcp *returns*. It cannot stop Dockhand writing the dump, and
UI- or scheduler-triggered actions write it too. Pair it with a drop rule in the log shipper
(see [dockhand.md](../foundation/dockhand.md#known-behaviour)).

## Input Validation

`container_id` and `stack_name` are validated against a safe-ID regex
(`^[a-zA-Z0-9][a-zA-Z0-9_\-\.]*$`) before being interpolated into URL paths, which prevents
path traversal such as `../health`. Query parameters use `httpx`'s `params=` dict, which
prevents query injection.

## Configuration

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `DOCKHAND_ENDPOINT` | yes | — | Base URL, e.g. `http://localhost:7777` |
| `DOCKHAND_API_TOKEN` | yes | — | Dockhand API token (UI: Settings → API Tokens); valid for every environment |
| `DOCKHAND_DEFAULT_ENV` | effectively yes | — | Default environment id |
| `DOCKHAND_ALLOWED_ENVS` | no | — | Comma-separated environment ids this instance may reach; unset = no pin |
| `MCP_TRANSPORT` | no | `stdio` | `http` for the PM2 service |
| `DOCKHAND_MCP_HTTP_HOST` / `_PORT` / `_PATH` | no | `127.0.0.1` / `8505` / `/mcp` | HTTP bind (loopback only) |
| `DOCKHAND_MCP_BEARER` | yes in `http` | — | Bearer the endpoint requires (≥ 16 chars) |
| `DIGEST_PIN_REPORT` | no | `~/.local/state/digest-pin-check/report.json` | Digest-pin report path. Env only, never a tool argument |
| `DIGEST_PIN_MAX_AGE_H` | no | `30` | Report age past which pins read `not_assessed` |
| `LOG_FILE` / `LOG_LEVEL` | no | per-app log file / `INFO` | See Observability |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | — | Per-tool tracing spans (`dockhand-mcp[otel]`) |
| `INFLUXDB_URL` / `INFLUXDB_TOKEN` / `INFLUXDB_BUCKET` | no | — / — / `dockhand-mcp` | InfluxDB metrics (`dockhand-mcp[influxdb]`) |
| `NATS_URL` / `NATS_SUBJECT_PREFIX` | no | — / `dockhand` | NATS events |

The ecosystem file reads the token, both bearers, and telemetry endpoints from a secrets env
file at load time, so no secret is hardcoded in it. `NATS_URL` is deliberately not wired
through. With a per-user-auth NATS server and no dedicated user provisioned, the bare URL
causes an infinite reconnect loop.

## Dependencies

- **Dockhand** on `localhost:7777`. Remote environments are reached through Dockhand's
  Hawser agents, not directly.
- **scoped-mcp** fronts both instances.
- **Digest-pin checker** (optional) supplies the `pin_assessment` report.

## Operations

```bash
pm2 list | grep dockhand-mcp
pm2 logs dockhand-mcp --lines 50
pm2 restart dockhand-mcp            # or dockhand-mcp-fleet

# Loopback-only, bearer enforced
ss -tlnp | grep -E ':8505|:8510'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8505/mcp   # expect 401
```

`mcp_proxy` freezes the upstream tool list at proxy start. A release that adds tools is
invisible to callers until the proxy restarts, even though the service looks healthy.

## Observability

Structured logging (structlog, JSON-L) is always on, with **one sink** since 0.4.0. The file
handler is used when `LOG_FILE` is writable, and stderr is the fallback (or set
`LOG_FILE=''` to hand files to PM2). Each PM2 app has its own log file, rotated by the
host's logrotate config. `httpx`, `httpcore`, `mcp`, and `nats` are pinned to `WARNING`
whatever `LOG_LEVEL` is.

A configured backend that fails warns once and is then disabled for the life of the
process. An unset backend is disabled silently. A warning means "configured but broken".
`InfluxDBClient3` constructs lazily, so a wrong `INFLUXDB_URL` only shows up as
`influx_write_failed` on the first write. Check for that, not just process uptime.

## scoped-mcp integration

| Agent | Instance | Tool surface | Gating |
|-------|----------|--------------|--------|
| sysadmin | main (`:8505`) | all 30 tools (no list) | HITL on `container_action`, `stack_action`, `update_container`; rate limits `container_action` 10/minute, `update_container` 3/hour |
| fleet | pinned (`:8510`) | allowlist of 27 read tools. No `container_action`, `stack_action`, or `update_container` | none needed. Deploy verbs come later, HITL-gated |

No other agent manifest loads dockhand-mcp. The sysadmin desktop-session manifest carries
the same entry and rate limits.

```yaml
dockhand-mcp:
  type: mcp_proxy
  config:
    url: http://localhost:8510/mcp
    headers:
      Authorization: "Bearer ${DOCKHAND_MCP_FLEET_BEARER}"
    tool_allowlist:
      - get_health
      - list_containers
      # … read tools only
```

HITL-rejected attempts count against the rate limit. One mistaken `update_container` plus
two approval round-trips can spend the hour.

## Security

- **2026-05-25 audit** (3 findings): a PAT in `.git/config` (remote switched to SSH), path
  traversal via `container_id`/`stack_name` (safe-ID regex), and query injection via
  `environment_id` (`httpx params=`). All resolved.
- **0.4.0 observability hardening:** 0 Critical/High/Medium, 1 Low (`exc_info` on log sites,
  resolved).
- **0.5.0:** layered `inspect_container` redaction. An earlier key-name-only version was
  defeated in review before shipping.
- **0.8.0:** env-dump masking closes the gap where `get_container_logs` on the Dockhand
  container returned the raw `.env` dump into agent context and traces. Environment pinning
  closes the gap where a call with no `environment_id` from the fleet agent reached the
  local host. Audit: 1 Low + 4 Info — 1 fixed, 3 accepted (including the `since`/`until`
  residual above), 1 deferred.

## Related Docs

- [dockhand.md](../foundation/dockhand.md): the Dockhand service
- [scoped-mcp.md](../agent/scoped-mcp.md): the agent proxy that fronts both instances
