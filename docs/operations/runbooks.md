# Forge Operational Runbooks

Two types of runbooks exist on forge:

1. **Agent runbooks** — structured diagnostic procedures in the `forge-runbooks` Gitea repo, executable by agents via `/runbook <name>`
2. **Operator reference** — inline procedures for manual use (below)

---

## Agent Runbooks

### Repository

Gitea: `host-forge/runbooks`  
Local: `~/repos/gitea/host-forge-runbooks/`  
QMD collection: `forge-runbooks` (refreshed hourly by `qmd-refresh` PM2 cron)

### Invoking a runbook

From any agent session:

```
/runbook <name>
```

The `runbook` skill fetches the named runbook from the `forge-runbooks` QMD collection (falling back to direct file read), executes each step, and reports a PASS/FAIL summary table.

If no name is given, the skill lists available runbooks from `forge-runbooks/index.md`.

### Available runbooks

| Name | Description | Scope |
|------|-------------|-------|
| `mcp-health` | Verify MCP tool access — scoped-mcp processes, manifest loading, end-to-end tool calls | sysadmin, research |
| `agent-workflow` | Verify agent workflow files — manifests, skills, settings | sysadmin |
| `memory-pipeline` | Verify memory promotion, sync, and indexing chain | sysadmin, research |
| `docker-stack` | Verify Docker stack health and container state | sysadmin |
| `nats-health` | Verify NATS server, JetStream, and agent-bus connectivity | sysadmin |

### Runbook format

Each runbook file has YAML frontmatter (`name`, `description`, `scope`, `severity`, `tags`) followed by sections:

- **When to run** — trigger conditions
- **Steps** — ordered steps with bash commands, expected output, and FAIL criteria
- **Pass criteria** — overall pass definition
- **Common failures** — symptom → cause → fix table

### Adding a runbook

1. Create `~/repos/gitea/host-forge-runbooks/<name>.md` following the format above
2. Add a row to `forge-runbooks/index.md`
3. Add a row to the skill's available runbooks table: `agent-platform-skills/runbook/SKILL.md`
4. Commit both repos to main; QMD will index on the next hourly refresh

---

## Operator Reference

Common operational tasks for manual execution on forge. Each section is self-contained.

---

## Agent Operations

### Restart a resident agent
Resident agents (sysadmin, research, developer, writer, security) run as Claude Code projects dispatched via Matrix. They do not run as persistent PM2 processes.

To restart a stuck agent: send a new message to its Matrix room from the operator account. The dispatcher picks up the next message and starts a fresh session. No PM2 involvement.

### Restart a PM2 service
```bash
pm2 restart <service-name>
pm2 logs <service-name> --lines 50
```

HITL-gated services (scoped-mcp restart/stop calls) require CLI approval:
```bash
scoped-mcp hitl list
scoped-mcp hitl approve <request-id>
```

### Approve a HITL-gated action
When a sysadmin agent triggers a high-impact tool call, scoped-mcp suspends it and sends a Matrix notification.
```bash
scoped-mcp hitl list          # see pending requests
scoped-mcp hitl approve <id>  # approve
scoped-mcp hitl reject <id>   # reject
```

---

## Docker Stack Operations

### Redeploy a stack after image update
```bash
cd ~/docker/<stack-name>
docker compose pull
docker compose up -d
docker compose ps
```

Or via dockhand-mcp (sysadmin agent, HITL-gated):
```
dockhand-mcp: stack_action(stack_name="<stack>", action="deploy", acknowledge_env_log=true)
```

Dockhand prints the stack's whole `.env` to its own log on every stack action, so prefer
`docker compose` for any stack with secrets in its `.env`. `deploy` defaults to `pull=False`
(plain `compose up -d`); pass `pull=true` for `--pull always`. See
[dockhand-mcp.md](../components/mcp-servers/dockhand-mcp.md#stack-actions).

### Check for available image updates
```bash
# Via dockhand web UI: dockhand.example.com (forward auth)
# Or via dockhand-mcp (returns only rows needing attention; include_all=true for every row):
dockhand-mcp: check_updates()
```

### View recent Docker activity
```bash
docker events --since 1h
# Or via dockhand-mcp:
dockhand-mcp: get_activity(limit=20)
```

---

## Certificate Management

Certificates are managed by SWAG using DNS-01 validation via Cloudflare. Renewal is automatic (Let's Encrypt, 90-day certs renewed at 60 days).

### Check certificate expiry
```bash
docker exec swag certbot certificates
```

### Force renewal
```bash
docker exec swag certbot renew --force-renewal
docker restart swag
```

---

## OpenBao Operations

OpenBao replaced HashiCorp Vault; see [foundation/vault.md](../components/foundation/vault.md).
It never auto-unseals — the seal watcher only alerts.

### Check seal status
```bash
docker exec openbao bao status
```

### Unseal (after every restart or reboot)
Run once per share until the threshold is met (2 of 3). Paste each share at the prompt —
never pass it as an argument, which puts it in `ps` and shell history.
```bash
docker exec -it openbao bao operator unseal     # share 1
docker exec -it openbao bao operator unseal     # share 2
```
Then restart any Vault-backed scoped-mcp brokers PM2 parked as `errored` while the store
was sealed (`pm2 list | grep errored`).

### Rotate a secret
```bash
docker exec -it openbao bao kv put secret/<path> key=<new-value>
# Then restart affected services that read the secret at startup
```

---

## Memory and Knowledge Base

### Trigger an immediate memory reindex
```bash
# memsearch/Milvus retired 2026-09-17 — qmd is the semantic index now
qmd update && qmd embed
# Or wait for the hourly qmd-refresh cron (0 * * * *)
```

### Refresh the docs cache
```bash
cd ~/scripts && python doc-sync.py
# Runs automatically nightly at 03:00 via doc-sync-daily PM2 cron
```

### Check QMD collection status
```bash
qmd status
qmd collection list
```

---

## Observability

### Check Loki logs for a service

Loki runs multi-tenant (`auth_enabled: true`), so every query needs an `X-Scope-OrgID`
header naming a tenant. Each host writes its own tenant (named after the host, e.g.
`host-a`, `host-b`). Data written before tenancy was turned on sits in Loki's default
`fake` tenant until it ages out of retention. Query several tenants at once by joining them
with `|`, for example `host-a|fake`. This needs `multi_tenant_queries_enabled: true` in Loki,
and live tail does not work with a multi-tenant header.

```bash
# Grafana: grafana.example.com → Explore → pick the Loki datasource for the host.
# Each datasource sets X-Scope-OrgID itself; there is one datasource per tenant set.

# logcli
logcli query --org-id='host-a' --since=1h '{service_name="<name>"} | json | level="error"'
logcli query --org-id='host-a|fake' --since=30m '{container="<container>"} |= "ERROR"'

# curl against the Loki API
curl -sG -H 'X-Scope-OrgID: host-a' http://127.0.0.1:3100/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="<name>"} |= "ERROR"' \
  --data-urlencode "start=$(date -d '-1 hour' +%s)000000000"

# List the labels a tenant has (a quick "is this tenant receiving anything" check)
curl -s -H 'X-Scope-OrgID: host-a' http://127.0.0.1:3100/loki/api/v1/labels
```

A query with no `X-Scope-OrgID` header is rejected (`no org id`). A query against the wrong
tenant returns an empty result, not an error. If a query comes back empty, check the
tenant first. Container logs carry `container`, `stack`, `compose_service`, and `service_name`
labels (not `container_name`); list them with the `/labels` call above.

### Check InfluxDB metrics
Dashboard: grafana.example.com (OIDC via Authentik)

### Check NATS JetStream health
```bash
docker exec nats nats server info
docker exec nats nats stream ls
```

---

## Snapshot Monitoring

Btrfs snapshot space is watched by two probes, not one — see
[snapshot-monitoring.md](../components/platform/snapshot-monitoring.md) for full detail.
The older `snapshot-space-probe.sh` (a single `df`-based check) is retired.

### Check current snapshot capacity and bloat
```bash
pm2 show snapshot-capacity-probe
pm2 show snapshot-bloat-probe

# Direct check (no InfluxDB round-trip)
sudo btrfs filesystem usage /
```

### Force a probe run
```bash
pm2 restart snapshot-capacity-probe
bash -x ~/scripts/snapshot-bloat-probe.sh   # verbose, safe to run ad hoc
```

### Investigate a capacity or bloat alert
```bash
cat <appdata>/snapshot-probe/capacity.state  # debounce state, last tier + timestamp
tail -f ~/logs/snapshot-retention.log            # pruning activity
```

If `snapshot-capacity-probe` alerts critical, check `sudo btrfs filesystem usage /` for
`Device unallocated` before assuming actual data pressure — a full allocation with free
unallocated space usually means `btrfs balance`, not deleting snapshots.

---

## Backup and Recovery

### Atlas NFS mount
Atlas (NAS) is mounted at `/mnt/atlas/forge` via NFS from `<nas-ip>:/mnt/storage/forge`.

```bash
mount | grep atlas          # verify mount is active
ls /mnt/atlas/forge         # check accessible
```

If unmounted:
```bash
sudo mount -a               # re-mount from /etc/fstab
```

### Appdata layout
See [appdata-layout.md](appdata-layout.md) for the full appdata directory structure.

### Docker stack backups
See [docker-stack-backup.md](../components/foundation/docker-stack-backup.md). Quick checks:
```bash
~/scripts/docker-stack-backup.sh --dry-run          # tonight's plan: tiers, snapshot plan per stack
~/scripts/docker-stack-backup.sh --coverage-report  # what is and isn't covered (read-only)
jq '{outcome, coverage: .coverage.status}' "$BACKUP_DEST/$(hostname)/status.json"
sudo ~/scripts/docker-stack-restore.sh              # restore wizard (tar or restic source)
```

---

## Adding a New Stack

1. Create `~/docker/<stack-name>/docker-compose.yml`
2. Add secrets to `~/.secrets/forge.env` if needed
3. Add to NFS backup scope in Atlas config
4. Add to `~/docs/doc-sync.yml` if official docs exist
5. Update `~/repos/gitea/host-forge-knowledge-base/stacks/stack-inventory.md`
6. Update `~/repos/gitea/host-forge-knowledge-base/services.md` port registry
7. Deploy: `cd ~/docker/<stack-name> && docker compose up -d`
