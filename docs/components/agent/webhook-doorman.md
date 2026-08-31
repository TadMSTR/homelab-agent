# webhook-doorman

A fail-closed inbound webhook router. It replaces three separately-invented forge webhook
receivers — `vikunja-webhook-listener`, `qmd-webhook`, and `plane-webhook-listener` — with one
ingress that verifies, deduplicates, and fans out webhook deliveries to chat/notification sinks.
Public repo: [TadMSTR/webhook-doorman](https://github.com/TadMSTR/webhook-doorman).

- **Image:** `ghcr.io/tadmstr/webhook-doorman:0.4.0` (multi-arch amd64 + arm64) — verified
  deployed via `docker ps` (container start time postdates the v0.4.0 tag commit)
- **Compose:** `~/docker/webhook-doorman/docker-compose.yml` (own stack)
- **Config:** `/opt/appdata/webhook-doorman/config.yml` (0644, non-secret)
- **Secrets:** `/opt/appdata/webhook-doorman/.env` (0600 ted:ted, read by the daemon as root via
  `env_file`)
- **Data:** `/opt/appdata/webhook-doorman/data` (0755, owned 10001:10001 — SQLite in WAL mode)

## Port / Endpoint

`127.0.0.1:8507` → container `8080`. The loopback publish is for host-side smoke tests and admin
only — public traffic arrives via `vikunja-hooks.helmforge.me` through SWAG, which reaches the
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
| `push` | ntfy | `https://ntfy.glitch42.com`, topic `NTFY_TOPIC` |

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

## Configuration

`config.yml` sections: `server` (max body size, `allow_unverified`), `storage` (SQLite path,
retention: 30d events / 90d DLQ), `delivery` (5 attempts, exponential backoff 2s→300s, 10s
timeout), `admin` (`ADMIN_TOKEN` gate), `sources`, `sinks`.

Secrets live in `/opt/appdata/webhook-doorman/.env`: `GITHUB_WEBHOOK_SECRET`,
`VIKUNJA_WEBHOOK_SECRET`, `GRAFANA_WEBHOOK_TOKEN`, `MATRIX_TOKEN`, `NTFY_TOPIC`, `ADMIN_TOKEN`.

`dedup.id_header` must never point at a credential-bearing header — pointing it at one would get
that header redacted before storage, collapsing every event onto one dedup id and silently
dropping all but the first delivery. This is now a startup error, not just a convention.

## Health and Observability

- `GET /health` — `200` unless the router genuinely cannot serve (zero enabled sources, or an
  unreachable store); a source disabled for a missing secret still reports `200` with the reason
  named. **`503` is a real, docker-healthcheck-visible outcome**, not a constant `"ok"`.
- `GET /admin/dlq` — dead-letter queue, gated by `ADMIN_TOKEN`.
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

Built across four phases against the same repo, in order:

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

Forge went straight from `0.1.0` to `0.3.0` in one rollout once all three follow-on plans closed,
rather than deploying each intermediate version; v0.4.0 deployed separately. Full phase docs
(host-forge-knowledge-base, private): `phases/forge-webhook-router-2026-08.md`,
`phases/webhook-doorman-correctness-2026-08.md`, `phases/webhook-doorman-sinks-2026-08.md`,
`phases/webhook-doorman-observability-2026-08.md`,
`phases/webhook-doorman-agent-content-safety-2026-08.md`.

## Related Docs

- `services.md` (host-forge-knowledge-base) — port registry entry (8507)
- [matrix-mcp.md](matrix-mcp.md) — Matrix sink credentials share the same homeserver
- [task-queue-mcp.md](task-queue-mcp.md) — Vikunja events feed agent-facing task routing via this
  router's `vikunja-chat` sink
