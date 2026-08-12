# forge-configs

Version-controlled non-secret config files for forge Docker services, with Vault KV backing for secrets.

---

## What it is

`forge-configs` is a Gitea repo (`host-forge/configs`) that tracks SWAG nginx configuration and Grafana provisioning files from `/opt/appdata`. It separates non-secret configs (version-controlled in git) from secrets (stored in Vault KV at `secret/data/forge/docker/<service>`). The deploy script merges both — pulling configs from the repo and secrets from Vault — to produce the live service configuration.

The repo also serves as the source of truth for Phase 2f of `agent-workspace-scan`: the scanner checksums all tracked files hourly against the repo copies and alerts on divergence, catching out-of-band edits to `/opt/appdata` that bypass the git workflow.

---

## Endpoint / Location

| Item | Value |
|------|-------|
| Repo path | `~/repos/gitea/host-forge-configs/` |
| Gitea remote | `gitea.tadmstr.me/host-forge/configs` |
| Deploy script | `~/scripts/forge-configs-deploy.sh` |
| Log | `~/.claude/logs/forge-configs-deploy.log` |
| Vault KV mount | `secret/data/forge/docker/<service>` (KV v2) |

---

## Tracked Files

| Repo path | Source in `/opt/appdata` | Notes |
|-----------|--------------------------|-------|
| `appdata/swag/nginx/nginx.conf` | `swag/nginx/nginx.conf` | Top-level nginx config |
| `appdata/swag/nginx/proxy.conf` | `swag/nginx/proxy.conf` | Proxy header settings |
| `appdata/swag/nginx/ssl.conf` | `swag/nginx/ssl.conf` | TLS/cipher config |
| `appdata/swag/nginx/resolver.conf` | `swag/nginx/resolver.conf` | DNS resolver |
| `appdata/swag/nginx/worker_processes.conf` | `swag/nginx/worker_processes.conf` | Worker tuning |
| `appdata/swag/nginx/authentik-*.conf` | `swag/nginx/authentik-*.conf` | Authentik auth integration |
| `appdata/swag/nginx/authelia-*.conf` | `swag/nginx/authelia-*.conf` | Authelia auth integration |
| `appdata/swag/nginx/site-confs/*.conf` | `swag/nginx/site-confs/` | Default site configs |
| `appdata/swag/nginx/proxy-confs/*.conf` | `swag/nginx/proxy-confs/` | Per-service reverse proxy configs |
| `appdata/observability/grafana/provisioning/datasources/datasources.yml` | `observability/grafana/provisioning/...` | Grafana data sources |
| `appdata/observability/grafana/provisioning/dashboards/dashboards.yml` | `observability/grafana/provisioning/...` | Dashboard provider config |
| `appdata/observability/grafana/provisioning/dashboards/forge/*.json` | `observability/grafana/provisioning/...` | Dashboard JSON definitions |
| `docker/<service>/.env.example` | — | Env var schema only; actual values in Vault |

---

## Configuration

Vault AppRole credentials for the deploy script are sourced from `~/.secrets/forge-configs-vault.env` (auto-sourced by the script if `VAULT_ROLE_ID` and `VAULT_TOKEN` are not already set in the environment).

| Env var | Purpose |
|---------|---------|
| `VAULT_ADDR` | Vault address (default: `http://127.0.0.1:8200`) |
| `VAULT_ROLE_ID` | AppRole role ID for `forge-configs` policy |
| `VAULT_SECRET_ID_FILE` | Path to AppRole secret ID file |
| `VAULT_TOKEN` | Direct token (alternative to AppRole) |

Vault AppRole policy scope: `secret/data/forge/docker/*` (read only).

---

## Dependencies

- **Vault** at `http://127.0.0.1:8200` — must be unsealed for `.env` deployment; use `--skip-env` flag to deploy config files only when Vault is unavailable
- **git** — deploy script requires clean `main` branch before deploying
- **agent-workspace-scan** — Phase 2f reads this repo; scanner must have `~/repos/gitea/host-forge-configs/` accessible

---

## Operations

### Deploy all configs

```bash
~/scripts/forge-configs-deploy.sh
```

### Deploy a single service

```bash
~/scripts/forge-configs-deploy.sh --service swag
~/scripts/forge-configs-deploy.sh --service grafana
```

Available services: `swag`, `grafana`, `authentik`, `observability`, `vaultwarden`.

### Dry run (show changes without applying)

```bash
~/scripts/forge-configs-deploy.sh --dry-run
```

### Skip Vault .env deployment

```bash
~/scripts/forge-configs-deploy.sh --skip-env
```

### Add a new tracked config file

1. Copy the live file from `/opt/appdata` to the corresponding `appdata/` path in the repo
2. Add an `.env.example` under `docker/<service>/` documenting the variable schema
3. Commit to `main`
4. Add the path to the deploy script's service map
5. Ensure the scanner's Phase 2f config list covers the new file

### View deploy log

```bash
tail -f ~/.claude/logs/forge-configs-deploy.log
```

### Check for config drift

The agent-workspace-scan Phase 2f runs hourly and alerts to Matrix `#sysadmin` on any divergence between `/opt/appdata` and the repo. To check manually:

```bash
~/scripts/agent-workspace-scan.py 2>&1 | grep "Phase 2f"
```

---

## scoped-mcp integration

`forge-configs` is a Gitea repo — `githost-mcp` is used for git operations. Access no longer comes from a per-repo `AGENT_WORKSPACE.md` marker: build `githost-workspace-policy-2026-08` (2026-08-09) removed the 27 markers under `~/repos/gitea` in favor of the central `/etc/forge/workspace-policy.yml`. Access for this repo resolves from that policy's `~/repos/gitea` container root (`owning_agent: sysadmin`, `access: readwrite`, `inherit: false`, `pre_edit_skill: git-config-tracking`).

No agent has direct MCP access to forge-configs contents; the deploy script is invoked via `system-ops` or directly in sysadmin sessions. Phase 2f tamper detection provides passive coverage.

---

## Related Docs

- [agent-workspace-forge-2026-06 phase doc](../../phases/agent-workspace-forge-2026-06.md) — build that created this repo
- agent-workspace-scan — scanner that performs Phase 2f tamper detection
