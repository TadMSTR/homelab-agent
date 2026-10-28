# webhook-doorman

A fail-closed inbound webhook router. It replaces three separately-invented forge webhook
receivers — `vikunja-webhook-listener`, `qmd-webhook`, and `plane-webhook-listener` — with one
ingress that verifies, deduplicates, and fans out webhook deliveries to chat/notification sinks.
Public repo: [TadMSTR/webhook-doorman](https://github.com/TadMSTR/webhook-doorman).

- **Image:** `ghcr.io/tadmstr/webhook-doorman:0.7.0`, pinned by digest (multi-arch amd64 +
  arm64). The reference deployment runs 0.7.0 at time of writing, verified from the running
  container: its image ref, its `org.opencontainers.image.version` label (`0.7.0`) and
  `revision` label (the v0.7.0 merge commit), and `/health` reporting `"version": "0.7.0"`
- **Compose:** `~/docker/webhook-doorman/docker-compose.yml` (own stack)
- **Config:** `/opt/appdata/webhook-doorman/config.yml` (0644, non-secret)
- **Secrets:** `~/docker/webhook-doorman/.env` (0600, gitignored, read by the daemon as root via
  `env_file: .env`). It moved there from the appdata directory with the 0.7.0 upgrade, to
  follow the one-`.env`-per-stack convention, so a stack backup picks it up with the compose
  file
- **Data:** `/opt/appdata/webhook-doorman/data` (0755, owned 10001:10001 — SQLite in WAL mode)

## Port / Endpoint

`127.0.0.1:8507` → container `8080`. The loopback publish is for host-side smoke tests and admin
only — proxied traffic arrives via a dedicated webhook subdomain (e.g. `hooks.example.com`)
through SWAG, which reaches the
container by name over `forge-net`.

The port is 8507, not 8503: research verified 8503 free during preflight, but `doc-cache-mcp`
took it the same day before the build started. Registered in `services.md`.

## Sources

Three inbound webhook sources, each independently verified and each self-disabling (not erroring)
if its secret is unset:

| Source | Path | Verification | Sinks |
|--------|------|--------------|-------|
| `github` | `/webhook/github` | HMAC-SHA256 (`X-Hub-Signature-256`), dedup on `X-GitHub-Delivery` | `vikunja-chat` |
| `vikunja` | `/webhook/vikunja` | HMAC-SHA256 (`X-Vikunja-Signature`) | `vikunja-chat`, `push` |
| `grafana` | `/webhook/grafana` | Bearer token | `alerts` |

`qmd-webhook` was retired, not migrated — its only caller had been silently dead for 79 days
(agent-bus's emitter never reached the process serving tool calls, vikunja#444), and qmd exposes
no reindex-over-HTTP endpoint at any checked version. The hourly `qmd-refresh.sh` cron already
covers the reindex; see vikunja#445 if the sub-hour latency win is ever worth reimplementing.

## Sinks

| Sink | Type | Destination |
|------|------|-------------|
| `vikunja-chat` | Matrix | `MATRIX_ROOM_VIKUNJA`, template `{{ summary }}` |
| `alerts` | Matrix | `MATRIX_ROOM_ALERTS`, template includes `{{ firing_count }} of {{ alert_count }} firing` |
| `push` | ntfy | self-hosted ntfy (e.g. `https://ntfy.example.com`), topic `NTFY_TOPIC` |

Discord, Slack, and Apprise sinks also ship in the image (added in `webhook-doorman-sinks-2026-08`)
but are not configured on forge — no sink instance uses them in `config.yml` above.

Escaping is destination-specific, not format-specific: Discord Markdown is rendered *unescaped*
(Discord doesn't render raw HTML), while `apprise-api` Markdown is rendered *escaped* (its
Python-Markdown backend passes raw inline HTML through by spec). Each sink's escaping rule is
looked up per the full three-member format union — see `ARCHITECTURE.md` in the repo for the
detail that made this worth a doctrine statement.

## Agent-facing content safety (v0.4.0)

New in v0.4.0, and entirely opt-in — a config that doesn't mention these behaves exactly as
before.

- **`trust` on a source** — `untrusted` (default) | `trusted`. A verified signature proves who
  sent the request, not who wrote the body inside it.
- **`agent_readable` on a sink** — default `false`. When set alongside an `untrusted` source,
  the fields that source's parser marked attacker-authored arrive wrapped in
  `<untrusted source="..." field="...">`. Structural fields (`source`, `event_type`,
  `delivery_id`, `event_id`, and parser-derived values like `repo`/`number`) stay outside the
  fence. **Cost worth knowing:** a fenced field becomes a string, so under the `generic` parser
  — which marks the whole `payload` as untrusted — `{{ payload.issue.title }}` renders empty on
  an `agent_readable` sink. Use a named parser's context fields, which are fenced individually.
- **`filter` on a source** — `event_types` allowlist, `require`/`deny` over dotted paths into
  the decoded payload, `max_field_bytes`. Two asymmetries matter: a path that does **not**
  resolve **fails** a `require` (you asked for a guarantee the payload didn't carry) and
  **passes** a `deny` (absent isn't the thing being refused). A filtered event is stored with
  status `filtered` and zero deliveries, and answered `200`.
- **`detector` block** — `backend: none` (default) | `heuristic`, `threshold`,
  `on_detect: annotate|quarantine|drop`, `on_error: annotate|quarantine`. `on_error` has **no**
  `drop` member — deliberate: detection never rejects at the door, it only annotates or
  quarantines. The verdict is three-valued (`clean`/`flagged`/`unavailable`) and `unavailable`
  is never folded into `clean`, so a down detector doesn't read as clean traffic.
- **Two new admin endpoints**, behind the existing bearer token: `GET /admin/held` (metadata
  only — no payload, no rendered body, rule *names* only) and
  `POST /admin/release/{event_id}`.
- **Five new metric series**: `events_filtered_total{source,reason}`,
  `content_sanitized_total{source,class}`, `detection_total{source,verdict}`,
  `detection_latency_seconds{backend}`, `events_quarantined_total{source,rule}`, plus a
  `held_events` gauge.
- **`/health` gains a `detector` block** (`configured`, `backend`, `available`, `last_error`).
  `last_error` is an exception *class name* only, never a message — `/health` is
  unauthenticated.

**Deploy warning:** v0.4.0 applies the project's first schema migration automatically on first
container start. A rollback to 0.3.0 will **refuse to start** rather than write to a migrated
database. Snapshot `/opt/appdata/webhook-doorman/data` before any upgrade.

## Supply chain (v0.5.0)

Build-time and CI hardening only — **no runtime or behavioral change**. A 0.4.0 config runs
identically on 0.5.0: no new config keys, no new endpoints, no schema migration.

- **Dependency tree is now pinned and audited from what actually ships.** The image previously
  installed from a fresh, unpinned resolve at build time, while CI separately audited the
  *declared* version ranges — two different dependency sets, neither of which was the one
  published. A committed lockfile is now the source of truth for the build, and the audit runs
  against the artefact's own installed packages. No vulnerabilities were found; the gap closed
  was that nothing was actually looking at what shipped.
- **The publish path verifies the image before pushing it**, rather than building and pushing in
  one step with GHCR as the first thing to see the artefact.
- **CI now asserts the service's actual request-signing contract**, not just liveness: an
  unsigned request is refused, a wrongly-signed request is refused, and a correctly-signed
  request is accepted. The accept case is the one that matters — without it, a build whose
  verification logic rejected everything would pass identically to a working one.
- Base images pinned by digest, build provenance attestation, static analysis and dependency-bot
  coverage added, and the test coverage floor raised (with the measured figure recorded above
  the constant, so it can't drift silently again).

## Per-sink filters and review hardening (v0.7.0)

Every existing config loads unchanged, with two exceptions that are now startup errors: a
source listing the same sink twice, and a source `path` containing `{` or `}`.

### Per-sink filters

A source's `sinks:` entry may be a bare name (as before) or `{name, filter}`. The route filter
has the same `event_types` / `require` / `deny` gates as a source filter and runs **after** it:

- The **source** filter decides whether an event is admitted and stored.
- A **route** filter decides only whether *that* sink gets a delivery. `max_field_bytes` stays
  source-only, because every sink shares the one stored event.
- Values compare as text, so an integer payload value `3` matches `"3"` (Vikunja's priority is
  the integer at `data.task.priority`).
- An event every route refuses is stored as `filtered` with reason `sink`, answered `200`, and
  the response names the refusing sinks. Nothing is dropped silently.
- Each refusal logs `delivery_filtered` and increments
  `webhook_doorman_deliveries_filtered_total{source,sink,reason}`, after the dedup check so a
  producer retry isn't counted twice.
- Replay and release re-apply the routes to the stored payload.

The motivating case is one Vikunja webhook feeding a chat room tasks created and completed,
and a phone only new high/urgent tasks — previously that took a second webhook with its own
secret. The worked config is
[`examples/vikunja-chat-and-push.yml`](https://github.com/TadMSTR/webhook-doorman/blob/main/examples/vikunja-chat-and-push.yml)
in the repo; the reference is `docs/configuration.md`, "Per-sink filters". The reference
deployment's config does not use route filters yet.

### Image and CI gates

- **No pip in the image**, in the venv or the base image, asserted by `verify-image.sh` (which
  `ci.yml` and `publish.yml` both run) with a `python3` control so an empty listing can't pass.
- **Trivy gate**: HIGH/CRITICAL with a fix, no ignore file, over a `docker save` tarball, with
  package-count floors so a scan that recognised nothing fails. Shown red on the 0.6.0 image
  before being trusted green: most of 0.6.0's fixable findings were pip's vendored packages,
  which an audit of the installed tree can't see (vikunja#1033).
- **gitleaks gate** on PRs, pushes and a weekly full-history scan, with a pinned version and a
  prover that plants secrets in throwaway copies and requires each to be caught by the rule
  meant to catch it. Allowlisting is by value, not path. The pinned build flagged synthetic
  test fixtures a distro build had not, which is the reason to pin it.
- **Mutation gate** (mutmut) on `verification.py`, `secrets.py` and `filtering.py`, with
  per-module mutant floors and survivor ceilings; every remaining survivor was read and is
  equivalent. A test-suite guard also fails any test that touches the network.

### Behaviour changes

- **Replay refuses** events the detector dropped or quarantined, and events a filter refused
  (`not_replayable`). Quarantined events leave through `/admin/release` only.
- **Release is atomic**: two concurrent releases of one event queue one set of deliveries.
- **An interrupted dispatch resumes on redelivery.** If a failure lands between storing an
  event and queueing its deliveries, the producer's retry resumes it rather than being
  answered as a duplicate. Only events that were meant to reach sinks are resumed, to the
  sinks recorded at ingest.
- **Engine errors reach the DLQ.** A store write that fails around an attempt is logged,
  counted (`delivery_attempts_total{outcome="error"}`) and counts as an attempt, so a
  repeating failure dead-letters at `max_attempts` instead of looping.
- Every credential comparison (webhook verification, admin token, `/metrics` token) goes
  through one constant-time comparison over bytes; a non-ASCII credential is an ordinary 401.
- On an agent-readable sink, `summary` and `payload` are always fenced. The detector's
  `fence_forgery` rule version is now `2`, so stored verdicts say which rule set scored them.
- Matrix messages carry an empty `m.mentions` (event text can't ping a room), and Matrix
  transaction ids include a per-database id.
- **No `/docs`, `/redoc` or `/openapi.json`** — they listed every ingest path, unauthenticated.

**Upgrade warning:** 0.7.0 migrates the database to **schema v3** on first start (one column
and one small table, in a transaction; the startup log shows `store_ready` with
`migrated_from=2`). 0.6.0 refuses a newer schema, so snapshot the data directory before
upgrading if you want a way back.

## Configuration

`config.yml` sections: `server` (max body size, `allow_unverified`), `storage` (SQLite path,
retention: 30d events / 90d DLQ), `delivery` (5 attempts, exponential backoff 2s→300s, 10s
timeout), `admin` (`ADMIN_TOKEN` gate), `sources`, `sinks`.

Secrets live in the stack's `.env`: `GITHUB_WEBHOOK_SECRET`,
`VIKUNJA_WEBHOOK_SECRET`, `GRAFANA_WEBHOOK_TOKEN`, `MATRIX_TOKEN`, `NTFY_TOPIC`, `ADMIN_TOKEN`.

`dedup.id_header` must never point at a credential-bearing header — pointing it at one would get
that header redacted before storage, collapsing every event onto one dedup id and silently
dropping all but the first delivery. This is now a startup error, not just a convention.

## Health and Observability

- `GET /health` — `200` unless the router genuinely cannot serve (zero enabled sources, or an
  unreachable store); a source disabled for a missing secret still reports `200` with the reason
  named. **`503` is a real, docker-healthcheck-visible outcome**, not a constant `"ok"`.
- `GET /admin/dlq` — dead-letter queue, gated by `ADMIN_TOKEN`. The token is the control for
  every `/admin/` route; the loopback publish and proxy block are defence in depth.
- No OpenAPI surface: `/docs`, `/redoc` and `/openapi.json` are disabled (v0.7.0).
- `GET /metrics` — Prometheus exposition format, hand-written (no runtime `prometheus_client`
  dependency). Delivery/rejection counters and a delivery latency histogram. Unauthenticated by
  default (scrape convention) — a `metrics.token_env` shorter than expected leaves it open rather
  than closed, logged as a `metrics_unauthenticated` WARNING at every boot.
- Optional OpenTelemetry behind an `[otel]` extra. Traces to SigNoz via
  `OTEL_EXPORTER_OTLP_ENDPOINT=http://signoz-otel-collector:4318` (container-name routing over
  `forge-net`, not the host IP).

Redaction is enforced at every boundary a string crosses into storage or an exporter — ingest,
the DLQ error-message field, and OTel spans (webhook URLs and Apprise's `key` path segment are
credentials, and instrumenting `httpx` would otherwise put them straight into span attributes).

## Hardening

- `user: "10001:10001"` — stated explicitly so a future base-image change can't silently promote
  the container to root
- `read_only: true` root filesystem + tmpfs `/tmp` (16m); `/data` is the only other writable mount
- `cap_drop: [ALL]`, `no-new-privileges:true`
- `mem_limit: 256m`, `cpus: 0.5` — a ceiling, not a reservation; the router idles in single-digit MB
- Networks: `forge-net` (SWAG ingress + Matrix/ntfy egress) and `prometheus-scrape` (metrics-scrape
  only — `/metrics` stays unpublished on the host and unrouted through SWAG)

## Operations

```bash
# Status
docker compose -f ~/docker/webhook-doorman/docker-compose.yml ps

# Logs
docker compose -f ~/docker/webhook-doorman/docker-compose.yml logs -f webhook-doorman

# Restart (env changes need a recreate, not a bare restart)
docker compose -f ~/docker/webhook-doorman/docker-compose.yml up -d --force-recreate webhook-doorman

# Manual health check
curl -s http://127.0.0.1:8507/health

# DLQ (admin-gated)
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" http://127.0.0.1:8507/admin/dlq
```

## Build History

Built across four phases against the same repo, in order, plus one supply-chain-only release
with no separate phase doc:

1. `forge-webhook-router-2026-08` — original build, v0.1.0. Introduced the fail-closed model:
   escaping belongs to the destination (not the parser), a dedup key can't point at a credential
   header, and a `HOST`-bind guard that can't fail is worse than no guard.
2. `webhook-doorman-correctness-2026-08` — v0.1.1. Sink-secret discovery moved from a hardcoded
   field-name list to reflection over every sink's model fields; `/health` became a real
   pass/fail signal instead of a constant `"ok"`.
3. `webhook-doorman-sinks-2026-08` — v0.2.0. Added `discord`, `slack`, `apprise` sinks; fixed a
   two-way escaping branch over a three-member format enum.
4. `webhook-doorman-observability-2026-08` — v0.3.0. Added `/admin/dlq`, `/metrics`, delivery
   histograms, optional OTel — and closed a second credential leak the new tracing itself opened
   (OTel's automatic `httpx` instrumentation records full request URLs, which *are* the
   credential for Discord/Slack/Apprise webhook URLs).
5. `webhook-doorman-agent-content-safety-2026-08` — v0.4.0. Content-safety layer for
   destinations that feed an LLM agent (structural filtering, source trust + fenced untrusted
   content, Unicode instruction-smuggling sanitization, pluggable detector, quarantine/release)
   plus the project's first schema migration.
6. v0.5.0 — supply-chain hardening. Build-time dependency resolution replaced with a committed,
   hash-pinned lockfile audited from the published artefact; publish path verifies the image
   before push; CI asserts the accept/reject signing contract instead of only liveness. No
   behavioral change to the running service.
7. v0.5.1 and v0.6.0 — a dependency release, then the Python 3.14 image plus a fix that stops
   FastAPI 0.142's native OpenTelemetry from attaching a second span exporter on its own.
8. `webhook-doorman-review-2026-10` — v0.7.0. Per-sink filters, a full review at the current
   bar (three passes: security, correctness, test quality), a pip-free Trivy-gated image, a
   full-history gitleaks gate and a mutation gate. Three security audit rounds: round 2 caught
   a regression the round-1 fix had introduced (a fence-tag regex that backtracked
   quadratically), which is why re-checks are a required round and not a formality.

Forge went straight from `0.1.0` to `0.3.0` in one rollout once all three follow-on plans closed,
rather than deploying each intermediate version; v0.4.0, v0.5.0, v0.6.0 and v0.7.0 each deployed
separately. Full phase docs
(host-forge-knowledge-base, private): `phases/forge-webhook-router-2026-08.md`,
`phases/webhook-doorman-correctness-2026-08.md`, `phases/webhook-doorman-sinks-2026-08.md`,
`phases/webhook-doorman-observability-2026-08.md`,
`phases/webhook-doorman-agent-content-safety-2026-08.md`,
`phases/webhook-doorman-review-2026-10.md`.

## Related Docs

- `services.md` (host-forge-knowledge-base) — port registry entry (8507)
- [matrix-mcp.md](matrix-mcp.md) — Matrix sink credentials share the same homeserver
- [task-queue-mcp.md](task-queue-mcp.md) — Vikunja events feed agent-facing task routing via this
  router's `vikunja-chat` sink
