# dockhand-mcp

FastMCP Python MCP server wrapping the Dockhand REST API. Gives forge agents structured
access to Docker container, stack, image, volume, network, and host state, with the
ability to take container and compose stack actions.

- **Version:** 0.5.0, tagged 2026-09-07 — merged and tagged; the doc below describes the
  merged **code**, not necessarily the **running** service. Verified live: the PM2
  process's uptime predates this build and it has not been restarted since 0.4.0.
  Because `mcp_proxy` freezes its upstream tool list at proxy start, the 9 new tools
  below — and the `update_container` fix — are **not yet reachable through scoped-mcp**.
  The running service still exposes the old 9-tool surface, including the pre-0.5.0
  (broken) `update_container`. A sysadmin deploy/restart task closes this gap; check the
  PM2 process uptime against the deploy time before assuming any of 0.5.0 is live.
- **Repo:** `TadMSTR/dockhand-mcp` (public)
- **Transport:** long-lived PM2 HTTP service since 0.3.0, bound to `127.0.0.1:8505/mcp`
  and fronted by scoped-mcp via `url:` (the memsearch-mcp pattern). `stdio` remains the
  local-dev default (`MCP_TRANSPORT` unset).
- **Port:** `127.0.0.1:8505` in `http` mode; none in `stdio` mode
- **Auth:** `http` mode requires `DOCKHAND_MCP_BEARER` (≥ 16 chars) presented as
  `Authorization: Bearer`; startup fails closed on a non-loopback host, a missing
  bearer, or a too-short one. Dockhand itself is reached with `DOCKHAND_API_TOKEN`
  (from `forge.env`).
- **Agents:** all 5 forge agents via scoped-mcp `dockhand` module

## Tools

As of the 0.5.0 code (not yet deployed — see **Version** above), the surface is 18
tools. All are read-only except `container_action`, `stack_action`, and
`update_container`.

| Tool | Description |
|------|-------------|
| `get_health` | Dockhand server health and version |
| `list_containers` | List all containers with status, optionally filtered by environment |
| `list_stacks` | List Docker Compose stacks managed by Dockhand |
| `list_images` | All images: id, tags, size, created |
| `list_volumes` | All volumes: name, driver, mountpoint, labels |
| `list_networks` | All networks: name, driver, scope, attached containers |
| `get_host_info` | Docker host: hostname, IP, CPU, memory, uptime |
| `inspect_container` | Full container config — this server's own secret redaction is layered on top of Dockhand's, see [Secrets in inspect_container](#secrets-in-inspect_container) |
| `get_container_logs` | Combined stdout/stderr, `tail` bounded to 100 by default |
| `get_container_stats` | One-shot CPU / memory / network / block-IO snapshot |
| `get_stack_compose` | A stack's compose content and resolved compose/env paths |
| `get_pending_updates` | Containers with an image update available, from the last `check_updates` run — the one route where Dockhand documents `env` as required rather than optional |
| `container_action` | Perform an action on a container: `start`, `stop`, `restart`, `pause`, `unpause`, or `remove` |
| `stack_action` | Perform an action on a stack: `start`, `stop`, `restart`, or `deploy` — see [Stack Actions](#stack-actions) for `deploy`'s pull/build/force-recreate options |
| `check_updates` | Run an image update check across all containers (synchronous; contacts a registry per image, can be slow) |
| `update_container` | Pull and recreate a container with the latest image — see [Update Workflow](#update-workflow) |
| `scan_image` | Run a vulnerability scan on a container image |
| `get_activity` | Recent Dockhand activity log (deployments, restarts, etc.) |

The 9 tools added in 0.5.0 are: `inspect_container`, `get_container_logs`,
`get_container_stats`, `get_stack_compose`, `list_images`, `list_volumes`,
`list_networks`, `get_pending_updates`, `get_host_info` — all read-only.

Every tool except `get_health` and `get_activity` accepts an optional `environment_id`,
resolved as `explicit argument → DOCKHAND_DEFAULT_ENV → config error`.

## Stack Actions

`stack_action(..., "deploy")` gained three optional arguments in 0.5.0: `pull`,
`build`, `force_recreate`. Before this, `pull` was hardcoded `true` — equivalent to
`docker compose up -d --pull always` — which re-resolves every image on every deploy
and is believed to be the cause of past unexpected recreates of unrelated services in a
stack. Defaults are unchanged (`pull=True`, `build=False`, `force_recreate=False`), so
this is a new capability rather than a change in default behavior:

```python
stack_action("example-stack", "deploy")               # unchanged default: --pull always
stack_action("example-stack", "deploy", pull=False)    # plain `docker compose up -d`
```

Passing any of the three arguments to `start`/`stop`/`restart` is an error rather than a
silent no-op — those routes send no request body at all.

`deploy` is still whole-stack — there is no per-service scoping, because the underlying
REST route has no service parameter. That's an upstream limitation, not something a
future version of this server can fix on its own. **The standing operational rule still
applies:** for a single-service deploy, run `docker compose up -d <service>` directly
rather than through this tool.

## Asynchronous Actions

Only **`stack_action` with `start` or `stop`** returns a job ID that needs polling
(via `get_activity` / `GET /api/jobs/{jobId}`). Everything else — including
`stack_action(..., "deploy")`, `update_container`, and `check_updates` — responds
synchronously/directly. A returned `success: false` from any of these is a completed
failure, not a queued job to chase down.

## Update Workflow

`update_container` was **completely broken from v0.1.0 through 0.4.x — zero successes
against any container, ever**, not merely unreliable for one. It posted an incomplete
request body to `POST /api/containers/{id}/update`, which the Dockhand handler could not
use, and every real call returned a 500. Fixed in 0.5.0: it now posts to `POST
/api/containers/batch-update`, which performs the inspect/pull/recreate cycle
server-side with full config passthrough.

It does **not** shell out to `docker compose`. A compose-managed container is recreated
through the Docker API directly — measured against a live host, this does not orphan the
container from its compose project; the compose labels and config hash survive, and a
subsequent `docker compose up -d` reports no wanted change.

Recommended sequence:

```
1. check_updates()          # contacts a registry per image; can be slow
2. get_pending_updates()    # reads that result back later without re-running the check
3. scan_image(image)        # review CVE count before pulling
4. update_container(id)     # re-pulls and recreates the container in place
```

A container labelled `dockhand.update=false` now comes back as `{"success": true,
"skipped": true, "reason": "..."}` rather than being reported as a plain success — read
`skipped` explicitly rather than treating any `success: true` as "updated."

## Secrets in `inspect_container`

`inspect_container` returns full container config, including environment variables.
Dockhand's own documented secret-masking for this endpoint **does not work in this
deployment**: measured against the live host, secret-shaped environment variables came
back unmasked across every container tested. Dockhand only masks variables it recognizes
as a project's registered secrets, and stacks that supply environment via `env_file`
paths outside Dockhand's mount have none registered.

So this server does its own redaction on top, and it is layered rather than name-only —
an earlier, key-name-only version of this redaction was defeated by a security review
before it shipped (real passwords came back in the clear behind key names the name list
hadn't anticipated). The corrected, layered version:

| Rule | Effect |
|---|---|
| Credential-shaped key (`*PASS*`, `*TOKEN*`, `*SECRET*`, `*_KEY*`, `*AUTH*`, …) | Redacted, unless the value is structurally incapable of being a secret (flag, number, empty) |
| Any long opaque value | Redacted regardless of key name — catches names the key-list doesn't anticipate |
| Credentials embedded in URL values and query strings | Stripped |

It covers `Config.Env` and `Config.Labels`. **It does not cover `Config.Cmd`,
`Entrypoint`, or `Args`** — a credential passed on a command line still comes back in the
clear. Treat `inspect_container` output as sensitive regardless of the redaction layer,
and restrict which agents/callers can invoke it accordingly.

`get_container_logs` carries the same unredacted-secret risk as `docker logs` — there is
no key to match against in a log line, so no redaction rule can catch a secret printed
there.

## Input Validation

`container_id` and `stack_name` parameters are validated against a safe-ID regex before
being interpolated into URL paths:

```python
_SAFE_ID = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9_\-\.]*$')
```

Values that don't match are rejected with a clear error rather than being passed to
the API. This prevents path traversal (e.g., `../health`) via tool parameters.

Query parameters use `httpx`'s `params=` dict rather than f-string interpolation, which
prevents query injection via values containing `&`.

## scoped-mcp Registration

Since 0.3.0, registered as a `url:`-type `mcp_proxy` pointing at the PM2 HTTP service,
with the bearer token as a header:

```yaml
dockhand-mcp:
  type: mcp_proxy
  config:
    url: http://localhost:8505/mcp
    headers:
      Authorization: "Bearer ${DOCKHAND_MCP_BEARER}"
```

HITL gating on `container_action` / `stack_action` / `update_container` is applied by
scoped-mcp by tool name and is unaffected by the transport.

`mcp_proxy` freezes the upstream tool list at proxy start — a code deploy that adds
tools (as 0.5.0 does) is invisible to callers until the PM2 process is restarted, even
though the running service otherwise looks healthy.

## Observability

Structured logging (structlog, JSON-L) is always on.

**One log sink, not two (fixed in 0.4.0).** Through 0.3.x, logs went to **stderr and a
file simultaneously** — every line was written to both PM2's `error_file` and `LOG_FILE`,
producing two near-identical unrotated files. That was a defect, not configuration: a
reader who set up log shipping against the old behaviour needs to revisit it. As of
0.4.0 there is **one** sink — the file handler wins when `LOG_FILE` is writable, and
stderr is the fallback when it is not (an unwritable path, or `LOG_FILE=''` to hand the
files to PM2 entirely). The fallback is load-bearing: it is what keeps CI and
restricted-permission runners from crashing on an unwritable log path. Rotation is real
as of 0.4.0 (daily, rotate 14, copytruncate via the host's logrotate config) — the prior
`ecosystem.config.js` comment claiming rotation "with the pm2-logrotate module" described
a module that was never installed.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/opt/appdata/dockhand-mcp/logs/dockhand-mcp.log` | Log file path — the single sink when writable. Set to `''` to hand log files to PM2 and fall back to stderr. |
| `LOG_LEVEL` | `INFO` | This service's own log level. `httpx`, `httpcore`, `mcp`, and `nats` are pinned to `WARNING` regardless of `LOG_LEVEL` (since 0.4.0) — raising `LOG_LEVEL` to `DEBUG` now gets this service's own detail rather than its dependencies' wire trace. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | Enables per-tool tracing spans (`dockhand.tool.<name>`, via FastMCP middleware) into SigNoz (`pip install dockhand-mcp[otel]`). |
| `INFLUXDB_URL` + `INFLUXDB_TOKEN` | — | Enable InfluxDB metric emission (`pip install dockhand-mcp[influxdb]`). |
| `NATS_URL` | — | Enable NATS event publishing. |

The log directory is created automatically on startup.

**A configured-but-failing backend warns once and is then disabled for the life of the
process**, rather than being retried on every tool call — `_get_influx()` / `_get_nats()`
now cache a negative sentinel instead of silently `pass`ing on every failed connect. A
backend whose env var is simply *unset* is disabled silently, as before — that is the
intended "off" path, and the distinction matters to anyone reading logs: a warning means
"configured but broken," silence means "not configured." The warning carries the
exception class only, never the URL or token — a NATS URL embeds its own credentials.

**`INFLUXDB_URL` deserves an explicit warning.** `InfluxDBClient3` constructs **lazily**
and never contacts the host, so a wrong URL does not fail at startup — the service comes
up looking healthy, and the failure only surfaces on the first metric write
(`influx_write_failed`). This is not hypothetical: a misconfigured URL went unnoticed for
35 days on forge before the 0.4.0 build. The service having started is not evidence that
telemetry works — check for `influx_write_failed` in the logs, not just process uptime.

## Security

From audit 2026-05-25 (3 findings):

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | GitHub PAT embedded in `.git/config` remote URL | Remote switched to SSH (`git remote set-url`); PAT rotation pending (manual) |
| L1 | Low | `container_id` / `stack_name` unsanitized in URL paths (path traversal) | `_SAFE_ID` regex validation added to `container_action`, `stack_action`, `update_container` |
| L2 | Low | `environment_id` f-string in URL query (query injection) | Switched to `httpx params=` dict in `list_containers` and `list_stacks` |

**Note on M1:** The PAT has been removed from `.git/config` by switching to SSH remote.
PAT rotation (GitHub UI action) remains a pending manual step.

The 0.4.0 observability-hardening audit (2026-08-29) found 0 Critical/High/Medium, 1 Low
(pre-existing `exc_info=True` on three log sites, resolved as a split — the
credential-bearing NATS-shutdown site drops it, the two OTel import sites keep it as a
documented exemption), 2 Info. Full account:
`host-forge-knowledge-base/phases/dockhand-mcp-observability-hardening-2026-08-29.md`.

The 0.5.0 build's own security-relevant change is the redaction layering described above
under [Secrets in inspect_container](#secrets-in-inspect_container) — an earlier
key-name-only version was defeated by review before shipping.

## Related Docs

- [dockhand.md](../foundation/dockhand.md) — Dockhand service (the wrapped service)
- [forge-agent-mcp-restore.md](../../phases/forge-agent-mcp-restore.md) — scoped-mcp wiring
- `host-forge-knowledge-base/phases/dockhand-mcp-observability-hardening-2026-08-29.md` — the 0.4.0 build (private repo, phase doc)
