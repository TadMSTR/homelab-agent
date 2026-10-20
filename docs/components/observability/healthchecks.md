# Healthchecks

[Healthchecks](https://github.com/healthchecks/healthchecks) is a self-hosted cron-liveness
monitor. On forge, every job in the operator's user crontab runs under a small wrapper
(`hc-run.sh`) that pings Healthchecks when the job starts and again with its result. A job
that fails, or doesn't run on time, turns its check `down`. Prometheus scrapes the check
states and Grafana alerts on them.

Healthchecks does no alerting of its own. It has no notification integration configured, so
there's one rule engine (Grafana), one routing table and one place to silence.

- **Images:** `healthchecks/healthchecks:v4.4` and `postgres:17-alpine` (tag plus `@sha256`
  digest pinned for both)
- **Compose:** `~/docker/healthchecks/docker-compose.yml` (its own stack)
- **Appdata:** `/opt/appdata/healthchecks/postgres/` (database only)
- **Listener:** `127.0.0.1:8509` → container `:8000` (loopback only)
- **UI:** `https://hc.example.com` via SWAG, behind Authentik forward auth
- **Networks:** `healthchecks-internal` (internal: app + Postgres), `forge-net` (SWAG),
  `prometheus-scrape` (Prometheus)

### Why its own stack

Healthchecks is what reports that cron died, so it mustn't share a compose lifecycle with
the things it watches. It sits outside the `observability` stack on purpose. Bringing
observability down for an upgrade doesn't take cron liveness with it, and the reverse.

## Stack

| Container | Image | Role |
|-----------|-------|------|
| `healthchecks` | `healthchecks/healthchecks:v4.4` | Web UI, ping endpoint, Management API, Prometheus metrics. Runs migrations, `sendalerts` and `sendreports` under uWSGI at start |
| `healthchecks-postgres` | `postgres:17-alpine` | Database. Healthchecks v4.4 is Django 6.1, which needs PostgreSQL 15 or newer |

PostgreSQL, not SQLite: start and finish pings for every run come to roughly 15-18k writes a
day from several uWSGI workers plus `sendalerts`. The stack keeps its own database rather
than sharing one.

## Port / Endpoint

| Path | Who uses it | Auth |
|------|-------------|------|
| `http://127.0.0.1:8509/ping/<ping-key>/<slug>[/start\|/<rc>]` | `hc-run.sh` (every cron job) | Ping key in the URL |
| `http://127.0.0.1:8509/api/v3/...` | `hc-sync.py` | Read-write API key (`X-Api-Key`) |
| `http://healthchecks:8000/projects/<uuid>/metrics/` | Prometheus (`prometheus-scrape` network) | Read-only API key (Bearer) |
| `https://hc.example.com/` | Operator, browser | Authentik forward auth, then Healthchecks' own password login |

Cron pings go straight to the loopback port and never through SWAG. `PING_ENDPOINT` is set
to the loopback URL, but it only affects what the UI shows.

### Two logins, on purpose

The public route is SWAG → Authentik forward auth → Healthchecks' own login form.
`REMOTE_USER_HEADER` is **deliberately unset**. SWAG overwrites the Authentik header, but
`127.0.0.1:8509` bypasses SWAG. With header auth on, any process on the host could set the
header and act as the operator: pause checks, read the ping key, or silence cron alerting.

The direct path (host loopback, plus any container on `forge-net` or `prometheus-scrape`)
skips Authentik, so Healthchecks' password login is the only gate there. It's an accepted
risk.

**Login throttling:** Healthchecks allows 20 login attempts per email per 24 hours. Anyone
who can reach the form can therefore lock the operator out of the **UI** for a day. Pings,
the API and the Prometheus scrape aren't affected.

## Configuration

Secrets (`SECRET_KEY`, `DB_PASSWORD`) live in `~/docker/healthchecks/.env` (0600, not in
git). Everything else is set inline in the compose file.

| Variable | Value | Why |
|----------|-------|-----|
| `SITE_ROOT` | `https://hc.example.com` | Public URL |
| `ALLOWED_HOSTS` | `hc.example.com,127.0.0.1,localhost,healthchecks` | **Must be set explicitly.** The default is `SITE_ROOT`'s host only, which would return 400 for every cron ping (`Host: 127.0.0.1:8509`) and for the Prometheus scrape (`Host: healthchecks:8000`) |
| `SECURE_PROXY_SSL_HEADER` | `HTTP_X_FORWARDED_PROTO,https` | Behind SWAG, Django otherwise sees plain HTTP and CSRF fails on save |
| `PING_ENDPOINT` | `http://127.0.0.1:8509/ping/` | Display only |
| `DEBUG` | `False` | Upstream default is `True` |
| `REGISTRATION_OPEN` | `False` | Upstream default is `True`. The superuser was created by hand |
| `UWSGI_PROCESSES` | `2` | |
| `UWSGI_DISABLE_LOGGING` | `true` | See below |
| `PROMETHEUS_ENABLED` | `True` | The metrics endpoint is the alert path |
| `WEBHOOKS_ENABLED`, `SLACK_ENABLED`, `MATTERMOST_ENABLED`, `MSTEAMS_ENABLED`, `OPSGENIE_ENABLED`, `PAGERTREE_ENABLED`, `PD_ENABLED`, `ROCKETCHAT_ENABLED`, `SPIKE_ENABLED`, `VICTOROPS_ENABLED`, `ZULIP_ENABLED` | `False` | Upstream defaults these to `True`. No integration is used (Apprise and shell already default to `False`) |
| `EMAIL_*` | unset | No MTA on the host |

### Request logging is off

Every ping URL carries the project's ping key (`/ping/<key>/<slug>/...`). The uWSGI request
log goes to `docker logs`, and Alloy ships container logs to Loki. With request logging on,
about 10k log lines holding the key reached Loki on the first day. The fix was
`UWSGI_DISABLE_LOGGING=true` (errors are still logged) and a ping-key rotation. As a second
layer, Alloy's Docker pipeline also rewrites `/ping/<16+ char token>` to `<redacted>`, which
catches a re-enabled log or any other container echoing the URL.

### Keys

All three keys are created in Healthchecks and stored as files. None is in git, and none is
passed on a command line.

| Key | File | Used by |
|-----|------|---------|
| Project ping key | `~/.secrets/healthchecks-ping.key` (0600) | `hc-run.sh` |
| Read-write API key | `~/.secrets/healthchecks-api.key` (0600) | `hc-sync.py` |
| Read-only API key | Prometheus `credentials_file` (`nobody`, 0400) | Prometheus scrape. The RW key gets 403 on the metrics endpoint |

## Container Hardening

```yaml
# healthchecks
#   runs as the image's own hc user (uid 999), needs no capability
mem_limit: 768m
cpus: "1.0"
cap_drop: [ALL]
security_opt: [no-new-privileges:true]
ports: ["127.0.0.1:8509:8000"]

# healthchecks-postgres
#   same pattern as the other Postgres containers: the entrypoint needs these to chown the
#   data dir and drop to the postgres user, so `user:` is not set
mem_limit: 512m
cpus: "1.0"
cap_drop: [ALL]
cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]
security_opt: [no-new-privileges:true]
networks: [healthchecks-internal]   # internal: true, no host port
```

Postgres has a `pg_isready` healthcheck and `healthchecks` waits on it (`depends_on:
service_healthy`).

## Cron Integration

Three files in the scripts repo (`~/scripts/`) tie the crontab to Healthchecks:

| File | Role |
|------|------|
| `hc-run.sh` | Wrapper on every crontab line. Pings `/start`, runs the job, pings the result |
| `hc-checks.yml` | One row per wrapped job: exit codes that count as success, and grace |
| `hc-sync.py` | Daily (08:05) reconciler. Makes Healthchecks match the crontab and fails on any gap |

### hc-run.sh

```
hc-run.sh [--ok 0,1,3] <slug> -- <command> [args...]
```

A crontab line looks like:

```
30 * * * * cd ~ && ~/scripts/hc-run.sh --ok 0,3 agent-workspace-scan -- /usr/bin/python3 ~/scripts/agent-workspace-scan.py >> ~/.pm2/logs/agent-workspace-scan-out.log 2>&1
```

It pings `/ping/<key>/<slug>/start?rid=<uuid>`, runs the command, then pings
`/ping/<key>/<slug>/<rc>?rid=<uuid>`. `<rc>` is `0` if the job's exit code is in the `--ok`
set (default `0`), and the real exit code otherwise. Healthchecks treats `0` as success and
anything else as failure.

The wrapper is built so cron behaves exactly as it did without it:

- **Output is untouched.** The job's stdout and stderr are inherited, so the crontab's
  redirections still capture them. The wrapper prints nothing itself, apart from one stderr
  line if the ping key is missing.
- **The exit code is preserved.** The wrapper exits with the job's own code, never the
  reported one.
- **It never blocks the job.** If Healthchecks is down, the job still runs. Each ping is
  bounded (`curl -m 5`, at most one retry within 10 s), and a refused connection isn't
  retried. A missing or malformed key means the job runs unreported.
- **No ping bodies.** Job output can hold secrets, and Healthchecks stores bodies.
- **The key stays out of argv and the environment.** The URL is fed to `curl -K -` on stdin,
  so `/proc/<pid>/cmdline` shows only `-K -`. The key is held in a non-exported variable, and
  `curl -q --noproxy '*'` ignores `~/.curlrc` and proxy variables.

### hc-checks.yml

Keyed by slug. Schedules are **not** here: `hc-sync.py` reads each job's 5-field schedule
from the crontab, which is the only source of truth.

```yaml
defaults:
  ok: [0]
  grace_minutes: 15

checks:
  disk-space-probe: {}
  agent-workspace-scan: {ok: [0, 3]}   # 3 = ran, alerts raised and already sent
  btrfs-scrub-monthly: {grace_minutes: 480}
  doc-health: {grace_minutes: 40}      # claude -p, timeout 1200 s
```

- **`ok`:** exit codes reported as success. Widen it only for a code the job's own contract
  defines as "ran, and reported a finding it already alerts on". A code that means "couldn't
  do its work" stays a failure.
- **`grace_minutes`:** how late a ping may be before the check goes down, and how long a run
  may take after `/start`. The rule of thumb is `max(15, 2 × p95 runtime)`. The 15-minute
  floor covers the nightly backup, which stops the healthchecks stack for a few minutes.

### hc-sync.py

Runs daily at 08:05, itself under `hc-run.sh`, so a failed sync is a failed check and
therefore an alert. It upserts one check per wrapped crontab line through the Management API
(`POST /api/v3/checks/` with `unique=["name"]`). Each check gets the line's cron schedule,
timezone `America/New_York`, the grace from `hc-checks.yml`, and the tags `cron forge`.

It **exits 1** on anything that would leave a job unwatched or an alert untrustworthy:

- a crontab job line that isn't wrapped in `hc-run.sh` (`@`-schedules aren't supported)
- a wrapped slug with no `hc-checks.yml` row, or a row with no crontab line
- a line's `--ok` set that differs from its `hc-checks.yml` row
- a check in Healthchecks with no crontab line. Orphans are reported, never deleted
- a check still `new` (never pinged) after its second scheduled run plus grace
- a **paused** check. A paused check reports `hc_check_up 1`, so `CronJobDown` can never
  fire for it. hc-sync also re-asserts `manual_resume=false` on every check
- a failed API write

It exits 2 if it couldn't run at all (no crontab, no API key, API unreachable, bad config).

**First-seen tracking.** A `new` check reports `hc_check_up 1`, so a wrapped job that never
pings (a typo in the wrapper path, say) would otherwise stay silent forever. The v4.4
Management API returns no creation time (no `created` field), so hc-sync records when it
first saw each check in `~/.local/state/hc-sync/first-seen.json`, keyed by check UUID. A
check first seen today gets a full two-run window from today. That can delay a finding but
never invent one.

Before sending the RW key, hc-sync checks that Healthchecks is the thing answering on the
port (unauthenticated `/api/v3/status/` returns `OK`, and a keyless `/api/v3/checks/` returns
its own 401). It never follows a redirect with the key.

### Adding a cron job

A new cron job needs **both** of these, or hc-sync fails the next morning:

1. The `hc-run.sh <slug> --` prefix on the crontab line (plus `--ok` if the job has success
   codes other than 0).
2. A matching row in `hc-checks.yml` (with the same `ok` set).

Then run `hc-sync.py --dry-run` to preview, and `hc-sync.py` to create the check.

**Don't pause a check to silence it.** hc-sync fails on paused checks. A flapping or slow job
gets more `grace_minutes`, never a pause or a Grafana silence.

### Scope

Coverage is the **operator's user crontab only**. Not covered:

- root's `/etc/cron.d` jobs (the nightly Docker stack backup has its own status contract)
- anacron and systemd timers
- PM2 daemons

Root cron lines are to be wrapped when they're next touched. That needs a root-readable copy
of the ping key.

## Alerting

Prometheus scrapes the project metrics endpoint:

```yaml
- job_name: healthchecks
  scrape_interval: 60s
  metrics_path: /projects/<project-uuid>/metrics/
  authorization:
    type: Bearer
    credentials_file: /etc/prometheus/secrets/healthchecks_ro_key
  static_configs:
    - targets: ['healthchecks:8000']
  metric_relabel_configs:
    - source_labels: [name]
      regex: '.*[^a-z0-9_-].*'
      target_label: name
      replacement: invalid-check-name
```

The relabel matters because the `name` label is a check name, and the UI user, an RW-key
holder or a ping-key holder can all write one. Grafana's default notification template
prints labels raw, so any name outside the slug alphabet is replaced before it can reach
Matrix. The check still alerts, under a safe label.

Grafana rules (provisioned in `rules-forge.yaml`):

| Rule | Expression | Route | Notes |
|------|-----------|-------|-------|
| `CronJobDown` | `min by (name) (hc_check_up{job="healthchecks"}) < 1` | Default policy → webhook-doorman → Matrix | `for: 0s` (Healthchecks' grace is the slack). `noDataState: OK`: Healthchecks itself being down is `PrometheusTargetDown`'s job. The summary names the job and points at its log |
| `TelegrafStale` | No `docker_container_status` point from Telegraf in InfluxDB for 5 min | `route: selfmon` → ntfy (bypasses the doorman) | Added in the same build. Without it, the Telegraf-fed rules (container restarts, disk, memory) go silent when Telegraf stops writing. `noDataState: Alerting` |

If the Healthchecks target itself goes down, the existing `PrometheusTargetDown` selfmon rule
covers it.

**Grouping:** the root policy groups by `alertname` and `route` with a 5-minute
`group_interval`. While one `CronJobDown` is firing, a second job's failure reaches Matrix at
the next group update (up to 5 minutes later), not within the 30-second `group_wait`.

## Dependencies

- **Depends on:** its own Postgres. SWAG and Authentik for the UI only. Pings, the API and the
  scrape work without them.
- **Depended on by:** every wrapped cron job (which keeps running if Healthchecks is down),
  `hc-sync.py`, Prometheus (`healthchecks` job) and the Grafana `CronJobDown` rule.
- **Nightly backup:** the backup script stops and restarts this stack around 02:00. Pings in
  that window are refused (milliseconds, no retry), and the 15-minute grace floor absorbs the
  gap, so no false `CronJobDown`.

## Operations

```bash
# Restart
cd ~/docker/healthchecks && docker compose restart healthchecks

# Status and logs (errors only: request logging is off)
docker ps --filter name=healthchecks
docker logs --tail 100 healthchecks

# Is it answering? (unauthenticated)
curl -s http://127.0.0.1:8509/api/v3/status/        # → OK

# Preview what hc-sync would change, then apply
python3 ~/scripts/hc-sync.py --dry-run
python3 ~/scripts/hc-sync.py

# Which checks are down right now (via Prometheus)
docker exec prometheus wget -qO- \
  'http://localhost:9090/api/v1/query?query=hc_check_up{job="healthchecks"}==0'
```

To see why a job failed, open the check in the UI for its ping log (start/finish times and
exit codes). The job's own output is wherever its crontab line redirects it (for most jobs,
`~/.pm2/logs/<slug>-*.log`).

**UI locked out?** That's the login throttle (20 attempts per email per 24 hours). The
lockout clears on its own within the 24-hour window. Pings, the API and alerting carry on
regardless.

## scoped-mcp Integration

None. No agent has a Healthchecks tool. Agents see cron failures the same way the operator
does: as `CronJobDown` alerts in Matrix, or through `grafana-mcp` and Prometheus queries on
`hc_check_up`.

## Related Docs

- [prometheus.md](prometheus.md) — scrape configuration
- [grafana-alloy.md](grafana-alloy.md) — log shipping and the ping-URL redaction stage
- [telegraf.md](telegraf.md) — the metrics source `TelegrafStale` watches
- [swag.md](../foundation/swag.md) — reverse proxy
