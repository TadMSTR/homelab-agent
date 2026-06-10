# Forge Operational Runbooks

Two types of runbooks exist on forge:

1. **Agent runbooks** — structured diagnostic procedures in the `forge-runbooks` Gitea repo, executable by agents via `/runbook <name>`
2. **Operator reference** — inline procedures for manual use (below)

---

## Agent Runbooks

### Repository

Gitea: `host-forge/forge-runbooks`  
Local: `/home/ted/repos/gitea/forge-runbooks/`  
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

1. Create `/home/ted/repos/gitea/forge-runbooks/<name>.md` following the format above
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

To restart a stuck agent: send a new message to its Matrix room from `@ted:helmforge.me`. The dispatcher picks up the next message and starts a fresh session. No PM2 involvement.

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

Or via dockhand-mcp (sysadmin agent):
```
dockhand-mcp: stack_action(stack_name="<stack>", action="redeploy")
```

### Check for available image updates
```bash
# Via dockhand web UI: dockhand.helmforge.me (forward auth)
# Or via dockhand-mcp:
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

## Vault Operations

### Check Vault seal status
```bash
docker exec vault vault status
```

### Unseal Vault (after restart)
Vault auto-unseals via Vault Transit if configured. If manual:
```bash
docker exec -it vault vault operator unseal
# Enter unseal key(s) — requires threshold of keys
```

### Rotate a secret
```bash
docker exec -it vault vault kv put secret/<path> key=<new-value>
# Then restart affected services that read the secret at startup
```

---

## Memory and Knowledge Base

### Trigger an immediate memory index
```bash
pm2 restart memsearch-watch  # will poll immediately on start
# Or run directly:
memsearch index ~/.claude/memory
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
```bash
# Via grafana.helmforge.me → Explore → Loki
# LogQL examples:
{service="<name>"} | json | level="error" | last 1h
{container_name="<container>"} |= "ERROR" | last 30m
```

### Check InfluxDB metrics
Dashboard: grafana.helmforge.me (OIDC via Authentik)

### Check NATS JetStream health
```bash
docker exec nats nats server info
docker exec nats nats stream ls
```

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
See [appdata-layout.md](appdata-layout.md) for the full `/opt/appdata/` directory structure.

---

## Adding a New Stack

1. Create `~/docker/<stack-name>/docker-compose.yml`
2. Add secrets to `~/.secrets/forge.env` if needed
3. Add to NFS backup scope in Atlas config
4. Add to `~/docs/doc-sync.yml` if official docs exist
5. Update `~/repos/gitea/host-forge/stacks/stack-inventory.md`
6. Update `~/repos/gitea/host-forge/services.md` port registry
7. Deploy: `cd ~/docker/<stack-name> && docker compose up -d`
