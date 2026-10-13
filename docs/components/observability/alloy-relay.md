# alloy-relay

`alloy-relay` is a second Grafana Alloy container that terminates Loki pushes from a remote
fleet host (argus) and forwards them to forge's Loki. It collects nothing on forge. It
accepts pushes from the reverse proxy, forces the remote host's tenant and labels, strips
structured metadata, and is the only container that can push to Loki over the ingest
network.

It's kept separate from forge's collector ([`alloy`](grafana-alloy.md)) on purpose. That
container mounts `docker.sock` and sits on `forge-monitoring`, and an ingest path from the
LAN edge must not land there.

- **Image:** `grafana/alloy:v1.20.1` (tag plus `@sha256` digest pinned, same as `alloy`)
- **Compose:** `~/docker/observability/docker-compose.yml` (project `observability`)
- **Config:** `~/docker/observability/alloy-relay/config.alloy` (mounted `:ro`)
- **Listener:** `:3500` (container-internal, no published ports)
- **Networks:** `loki-relay` (SWAG + relay), `loki-ingest` (relay + Loki)

## Request Path

```
remote host Alloy
  │  HTTPS POST /loki/api/v1/push   (basic auth)
  ▼
SWAG  loki.example.com ── network: loki-relay
  │  proxy_pass http://alloy-relay:3500/loki/api/v1/push
  ▼
alloy-relay  loki.source.api :3500
  │  relabel → stage.tenant → structured_metadata_drop
  ▼  ── network: loki-ingest
Loki :3100   tenant = argus
```

### Proxy route

The SWAG route is push-only and has no Authentik forward auth:

- One exact location, `/loki/api/v1/push`, POST only. Everything else on the host returns 404.
- Basic auth (one htpasswd user per remote host) plus an `allow <host-ip>; deny all;` IP allowlist.
- `limit_req` 1r/s with burst 30 (429 beyond), `client_max_body_size 4m`.
- The route **clears `X-Scope-OrgID`**, so the client never chooses the tenant.
- The upstream URI is fixed. This also keeps the relay's raw-push routes
  (`/loki/api/v1/raw`, `/api/v1/raw`) unreachable, which matters because those routes skip
  relabel rules entirely.

### Networks

Both networks are created by hand as `--internal` and declared `external: true` in both the
observability and SWAG compose files. Recreating or taking down either stack then leaves the
other's attachment in place.

```bash
docker network create --internal --subnet 172.20.x.0/24 loki-relay    # swag + alloy-relay
docker network create --internal --subnet 172.20.y.0/24 loki-ingest   # alloy-relay + loki
```

Each network has exactly two members. SWAG can't reach Loki at all, and the relay is the
only pusher on `loki-ingest`. **Never add a third container to `loki-ingest`.** Loki's
tenant header routes requests but doesn't authenticate them, so anything on that network
could write to any tenant.

## Configuration

The pipeline has four components, all named after the host:

| Component | Role |
|-----------|------|
| `loki.source.api "argus"` | HTTP push listener on `0.0.0.0:3500`. gRPC pinned to `127.0.0.1`. `use_incoming_timestamp = true`, so a post-reboot journal replay keeps its own timestamps. Runs `loki.relabel.argus.rules` on each entry |
| `loki.relabel "argus"` | Label rules (below). Used only for its `rules` export (`forward_to = []`) |
| `loki.process "argus"` | `stage.tenant { value = "argus" }`, then `stage.structured_metadata_drop` |
| `loki.write "argus"` | Push to `http://loki:3100/loki/api/v1/push` with `tenant_id = "argus"` |

### Label rules

These rules were written before Loki went multi-tenant. Now that the tenant is the real
boundary, they stay as defence in depth:

1. **Drop all incoming `__` labels.** `loki.source.api` runs relabel rules *before* it strips
   `__` labels, so a pushed `__job_ok` would otherwise survive into step 2.
2. **Allowlist `job`.** A job that isn't `journal`, `technitium` or `container` is
   rewritten to `job="unlisted"`, not dropped, so a labelling mistake on the remote host
   shows up instead of vanishing. The allowlist doesn't overlap forge's own jobs (`docker`,
   `scoped-mcp`, `githost-mcp`).
3. **Force `host="argus"`.**
4. **Force `service_name="argus-<job>"`.** Otherwise remote lines would group with forge's in
   Grafana Logs Drilldown.
5. **Label-name allowlist (`labelkeep`).** Only
   `host|job|container|unit|level|identifier|service_name` survive. A label the remote host
   needs that isn't on this list gets dropped. Verify it arrives, then extend the regex. This
   also caps stream cardinality.

### Tenant

`stage.tenant` overwrites the tenant on every entry. `loki.write`'s `tenant_id` is only a
default: `loki.source.api` turns an incoming `X-Scope-OrgID` into the entry's tenant *after*
relabel rules run, so without `stage.tenant` a header that got past the proxy would decide
the tenant. Proxy header clearing and `stage.tenant` back each other up. Keep both.

### Structured metadata

Structured metadata is per-line and survives relabel rules. The relay drops a fixed list of
keys that forge uses as labels or query fields (`agent`, `stream`, `filename`, `stack`, ...),
plus names a reader could mistake for the line or the tenant (`line`, `ts`, `value`,
`__tenant_id__` and its common spellings).

The list is defence in depth and can't be complete. Alloy's `structured_metadata_drop` has
no wildcard, and Loki normalises key names *after* the relay, so a separator variant of a
listed key gets through. **The control is Loki:** the `argus` tenant override sets
`allow_structured_metadata: false`, so Loki refuses any entry that still carries structured
metadata. See [Loki tenancy](grafana-alloy.md#loki-tenancy).

## Container Hardening

```yaml
user: "473:473"          # the image's own alloy user
read_only: true
cap_drop: [ALL]
security_opt: [no-new-privileges:true]
mem_limit: 256m           # idle ~40 MiB; ingest is capped upstream by limit_req
cpus: 0.5
command:
  - run
  - /etc/alloy/config.alloy
  - --server.http.listen-addr=127.0.0.1:12345   # Alloy UI on container loopback only
  - --storage.path=/var/lib/alloy/data
tmpfs:
  - /var/lib/alloy/data:uid=473,gid=473,mode=0700
  - /tmp:uid=473,gid=473,mode=1777
```

No socket, no host log mounts, no published ports. Storage is tmpfs because the relay holds
nothing worth keeping (no positions file, and no WAL because Alloy's `loki.write` WAL is
experimental). Entries in flight are lost if the relay restarts. That's an accepted
trade-off. The UI listens on loopback so SWAG can reach `:3500` and nothing else. The
side effect is that Prometheus can't scrape the relay's own metrics.

## Adding a Remote Host

The config's header comment has the recipe. For host `<name>`:

1. **Relay:** copy the four `argus` blocks, rename them `<name>`, give `loki.source.api` the
   next port (3501, ...), and set `host=` and `stage.tenant` to `<name>`.
2. **SWAG:** add a basic-auth user and `allow <ip>` for the host, and a `map $remote_user` from
   user to relay port. The authenticated user then picks the listener, and the tenant never
   comes from the client. (With a single host, the map isn't built yet.)
3. **Loki:** add an `overrides.<name>` block in `loki-config/runtime-overrides.yaml`.
4. **Grafana:** add a `Loki (<name>)` datasource with header `X-Scope-OrgID: <name>|<name>-none`.

## Operations

```bash
# Restart
cd ~/docker/observability && docker compose restart alloy-relay

# Logs
docker logs --tail 100 alloy-relay

# Are remote entries being refused? (rate limits, disallowed structured metadata)
curl -s http://127.0.0.1:3100/metrics \
  | grep 'loki_discarded_samples_total.*tenant="argus"'

# What has landed in the remote tenant
curl -s -H 'X-Scope-OrgID: argus' \
  'http://127.0.0.1:3100/loki/api/v1/label/job/values' | jq
```

A 429 at the proxy means the remote host is over the `limit_req` budget. A per-entry 400
from Loki with reason `disallowed_structured_metadata` means the remote collector is
emitting structured metadata, which the remote host config must not do.

## Dependencies

- **Depends on:** Loki (`depends_on`), SWAG (the only route in), the two external networks
- **Depended on by:** the remote host's log collector. If the relay is down, pushes fail at
  the proxy (502) and it's up to the remote collector to retry.

## Related Docs

- [grafana-alloy.md](grafana-alloy.md) — forge's collector and Loki tenancy
- [loki-mcp.md](loki-mcp.md) — querying the remote tenant
- [swag.md](../foundation/swag.md) — reverse proxy
