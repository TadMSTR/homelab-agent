# OpenBao (secrets store)

OpenBao is the platform's secrets store. It holds the per-agent credential bundles that
scoped-mcp fetches at startup, plus the stack secrets that the config-deploy script merges
into service `.env` files. It replaced HashiCorp Vault 1.19 in October 2026.

This page keeps its old `vault.md` path so existing links still resolve. Clients still call
it "Vault" in places: the scoped-mcp credential source is `credentials.source: vault`, and
the address variable is still `VAULT_ADDR`.

- **Image:** `openbao/openbao:2.7.1`, pinned by digest
- **API / UI:** `127.0.0.1:8210` → container `:8200`, plain HTTP, loopback only
- **Network:** its own bridge network, not the shared reverse-proxy network
- **Storage:** integrated Raft, single node
- **Seal:** Shamir, 3 shares, threshold 2, unsealed by hand after every start
- **State:** a dedicated directory outside the shared appdata tree (this page uses
  `/srv/openbao/{config,data,audit}` as the example)

## Why OpenBao, and why a fresh install

- **Licence.** OpenBao is the Linux Foundation-hosted fork of Vault under MPL-2.0. Vault moved to
  the BSL in 2023.
- **Fresh Raft install, not an upgrade.** The old Vault used the `file` storage backend.
  OpenBao removed `file` storage in 2.7.0, and its migration guide only covers Vault 1.14.1.
  So the move was a new OpenBao instance on Raft, then a scripted re-import of the KV data
  (latest version of each secret, values held in process memory only, a verify pass that
  printed only `match: true|false` per key).
- **Clients didn't change.** OpenBao serves the Vault HTTP API. scoped-mcp's `hvac` client,
  the `X-Vault-Token` header, AppRole login and KV v2 reads all work unchanged. Consumers
  kept the `VAULT_ADDR` variable name and only changed its value. The `bao` CLI reads
  `VAULT_ADDR` / `VAULT_TOKEN` too (as well as `BAO_ADDR` / `BAO_TOKEN`).
- **The design goal** was no root token at rest anywhere and no unseal key on any host
  an agent runs on. The old setup had both: a root token and an unseal key in one
  user-readable env file, and a second copy of the unseal key on NFS for auto-unseal.

## Design choices

| Choice | Detail | Why |
|--------|--------|-----|
| Raft storage | `storage "raft"`, one node | Supported backend with `bao operator raft snapshot save` for backups. PebbleDB (new in 2.7) has no snapshot API yet |
| Shamir manual unseal | 3 shares, threshold 2. No two shares in one place, none on the host, the NAS, or any machine an agent runs on | Auto-unseal options left in 2.7 are `static` (a key file or env var), `transit` (a second OpenBao) or KMS plugins. While agents still share a uid with Docker access, a key the host can read buys nothing |
| No standing root token | The init root token was used for bootstrap, then revoked. A check script confirms that no token carries the `root` policy | A root token at rest is a full compromise waiting to be read |
| Authenticated break-glass | `breakglass` userpass login + 2 shares → `bao operator generate-root`. Tested once end to end on the live instance | OpenBao 2.6+ requires a valid token for `/sys/generate-root-token`. The unauthenticated endpoint stays disabled (the default). Userpass doesn't depend on the identity provider, so break-glass still works when SSO is down |
| Declarative audit device | `audit "file"` stanza in the server config, `log_raw = false` (values HMAC'd) | Since 2.3.2 audit devices can't be created through the API by default. Declaring it in config means it exists before init, so the very first write is audited |
| Loopback only | Published on `127.0.0.1`, own network, no reverse-proxy hostname | Every consumer is a host process on loopback. No container needs to reach it |
| OIDC operator login | Day-to-day admin through the SSO provider (Authentik), mapped to an `operator` policy: admin without root, 1 h TTL, 8 h max | Admin access is an ordinary, expiring, audited token |
| Container hardening | Non-root uid, read-only root filesystem, `cap_drop: ALL`, memory and CPU limits, `disable_mlock = true` | Recommended with Raft. No `IPC_LOCK` needed |

### Honest limit

Until the agents run under their own uids and outside the `docker` group, an agent process
could `docker exec` into the container or read its memory once it's unsealed. This design
removes the *standing* root token and the *on-disk* unseal key. It doesn't contain an agent
running as the operator's uid.

## Port / Endpoint

| Endpoint | Binding | Used by |
|----------|---------|---------|
| API | `127.0.0.1:8210` → container `8200` | scoped-mcp brokers, config-deploy script, snapshot job, seal watcher |
| UI | `http://localhost:8210/ui` | Operator, through an SSH tunnel (`ssh -L 8210:127.0.0.1:8210 <host>`) |
| Cluster | `127.0.0.1:8201` in-container | Raft (single node; not published) |
| Health | `GET /v1/sys/health` | Seal watcher, container healthcheck |

There's no SWAG hostname. Adding one later (for example `bao.example.com`) is one proxy conf
plus an OIDC redirect URI. It was left out on purpose while the store stays off the LAN.

## Configuration

Server config (`openbao.hcl`, mounted read-only). No secret belongs in it:

```hcl
ui            = true
disable_mlock = true

storage "raft" {
  path    = "/openbao/data"
  node_id = "node1"
}

# Plain HTTP inside the container; published on 127.0.0.1 only.
# disable_unauthed_generate_root_endpoints is left at its default (true).
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr     = "http://127.0.0.1:8210"
cluster_addr = "https://127.0.0.1:8201"

audit "file" "file" {
  options {
    file_path = "/openbao/audit/audit.log"
    log_raw   = "false"
    mode      = "0640"
  }
}

# Never "trace" in production: OpenBao logs request and response bodies at trace.
log_level = "info"
```

There's no `seal` stanza, so the seal is Shamir. A config change applies on `SIGHUP`
(`docker kill -s HUP openbao`). A restart works too, but it seals the store.

**Auth methods**

| Method | Who | Policy |
|--------|-----|--------|
| `approle` | Each scoped-mcp agent, the config-deploy script, the snapshot job | One policy per role (below) |
| `oidc` | Operator, via the SSO provider, bound to one group | `operator` |
| `userpass` | `breakglass` only. Stored as a bcrypt `password_hash`, so no plaintext ever reaches OpenBao | Only `sys/generate-root-token/attempt` and `/update` |

**Policies as code.** Policies live as `.hcl` files in a private repo, and an idempotent
bootstrap script applies them with an `operator` token. Root isn't needed. Agent policies
read one exact path each, never a wildcard:

```hcl
path "secret/data/agents/research" {
  capabilities = ["read"]
}
```

**KV layout** (v2 at `secret/`): `secret/agents/<agent>` for per-agent credential bundles,
`secret/agents/shared`, and `secret/<host>/docker/<stack>` for stack secrets.

**Audit log shipping.** Alloy tails the audit file (`job="openbao"`) into Loki. Logrotate's
`postrotate` sends `SIGHUP` to the container, because the file audit device reopens its file
on HUP.

## Dependencies

**Depends on:**
- Docker, plus the operator holding at least 2 of the 3 unseal shares
- The SSO provider ([Authentik](authentik.md)) for operator OIDC login. Break-glass doesn't
  depend on it
- NAS storage for Raft snapshots

**Depended on by:**
- scoped-mcp for every agent whose manifest has `credentials.source: vault`. These fail
  closed while the store is sealed
- The config-deploy script ([forge-configs.md](forge-configs.md)), for stack `.env` secrets
- The Raft snapshot job

## Operations

### Every start is sealed

A host reboot, `docker restart`, a Docker engine restart, a `compose up` that recreates the
container, or a crash all leave OpenBao sealed. The healthcheck is `bao status`, which exits
2 when sealed, so a sealed container shows as `(unhealthy)`, not restarting. Agents never
unseal it and never handle a share.

```bash
# Sealed or down?
curl -s 127.0.0.1:8210/v1/sys/seal-status | jq -c '{initialized, sealed, t, n, progress}'

# Unseal (operator only, twice, share pasted at the prompt — never as an argument,
# which would put it in `ps` and shell history)
docker exec -it openbao bao operator unseal
docker exec -it openbao bao operator unseal

# Confirm
curl -s 127.0.0.1:8210/v1/sys/health | jq -c '{initialized, sealed, version}'
```

If `seal-status` reports `initialized: false`, **stop**. The Raft data is missing or a new
container started on an empty directory. Running `operator init` would create a different,
empty store. Restore the data from a snapshot instead.

### After unsealing: restart the brokers

Against a sealed store, scoped-mcp exits in about 0.6 s at startup. That's under PM2's
default 1 s `min_uptime`, so PM2 marks each Vault-backed broker `errored` within seconds of
boot, and they don't come back on their own once the store is unsealed. Restart each
`scoped-mcp-<agent>` after unsealing, then check `scoped_mcp_status` shows the credential
source healthy. To make the brokers retry on their own, give them a PM2 restart policy that
keeps retrying. The scoped-mcp README covers it under "Sealed store at startup".

### Seal watcher (alert only)

`openbao-seal-watcher.sh` runs from cron every 5 minutes under the Healthchecks wrapper.
It polls `GET /v1/sys/health?sealedcode=200&uninitcode=200&standbycode=200` and sorts the
result into `unsealed`, `sealed`, `uninitialized` or `unreachable`:

- `sealed`, `uninitialized` or `unreachable` → a `critical` alert to the Matrix alerts room
  (with an ntfy fallback). It names the unseal procedure and repeats every 6 h while the
  state lasts.
- Back to `unsealed` → one "cleared" message.
- It **never unseals**. There's no share on the host for it to use, and that's the point.

It exits 0 in every observed state, so its Healthchecks ping measures that the watcher ran,
not that the store is unsealed. It replaced the old auto-unsealing
[vault-seal-watcher](vault-seal-watcher.md), now retired.

### Break-glass (root token for an emergency)

Only when the `operator` login can't do the job, for example when the SSO provider is down
and the OIDC config has to be fixed:

1. `bao login -method=userpass username=breakglass` (inside the container, with
   `HISTFILE` unset)
2. `bao operator generate-root -init`, then `bao operator generate-root` twice, entering
   one share at each prompt
3. `bao operator generate-root -decode=<encoded> -otp=<otp>`
4. Do the emergency fix only. Any token the root token mints is its child and gets revoked
   with it
5. `bao token revoke -self`, `unset BAO_TOKEN`, remove the token helper file
6. Run the root-token check again and expect `carrying root: 0`

If userpass itself is broken, the fallbacks are recovery mode (`bao server -recovery`) or
temporarily setting `disable_unauthed_generate_root_endpoints = false`. Neither has been
tested on production.

### Backup: Raft snapshots, not file copies

The state directory sits **outside** the shared appdata tree on purpose. The nightly Docker
backup stops every appdata stack to copy it, and stopping OpenBao seals it. Every night would
then end with a sealed store and errored brokers until someone unsealed it by hand.

Instead, a daily job logs in with its own `raft-snapshot` AppRole and runs
`bao operator raft snapshot save` to NAS storage. It verifies each snapshot (tar listing,
`SHA256SUMS`, Raft index), keeps 14, and revokes its token on exit. Snapshots are encrypted
with the barrier key, so they're useless without the unseal shares. 2.7.1 has no
`snapshot inspect` command, so the job does its own checks.

### Logs and health

```bash
docker ps --filter name=^openbao$ --format '{{.Status}}'   # (healthy) once unsealed
docker logs --tail 50 openbao
# Audit log: Loki, {job="openbao"}
```

## scoped-mcp integration

No agent gets an OpenBao token or an MCP tool for it. Each agent's scoped-mcp broker logs
in with its own AppRole and reads its own bundle once at startup:

```yaml
credentials:
  source: vault
  vault:
    addr: "${VAULT_ADDR}"        # e.g. http://127.0.0.1:8210
    auth: approle
    role_id_env: VAULT_ROLE_ID
    secret_id_env: VAULT_SECRET_ID
    path: "agents/{agent_type}"  # relative to the secret/ KV v2 mount
    kv_version: 2
```

- **One AppRole and one policy per agent**, with `read` on `secret/data/agents/<agent>` only.
  No wildcard: a shared `secret/data/agents/*` policy would let every agent read every
  other agent's bundle. To test the scoping, probe agent X's AppRole against agent Y's path
  (expect a 403), and run the same probe against X's own path (expect success), so a broken
  probe can't pass as a denial.
- An operator tool mints the AppRole pairs and writes them, together with `VAULT_ADDR`, into
  each agent's env file in a single write. A half-written file (new credentials, old
  address) would be an outage.
- The store is sealed after any restart, and scoped-mcp then fails closed (`CredentialError`
  at startup). See "After unsealing" above.
- Until each agent runs under its own uid, the AppRole pairs sit in files the shared uid
  can read, so one agent could still log in as another. Per-agent policies limit what each
  pair can read. They don't stop a pair being used by the wrong process.

## Related Docs

- [vault-seal-watcher.md](vault-seal-watcher.md): the retired auto-unseal watcher
- [forge-configs.md](forge-configs.md): config-deploy script (stack secrets from KV)
- [authentik.md](authentik.md): SSO provider for the operator OIDC login
- [../agent/scoped-mcp.md](../agent/scoped-mcp.md): per-agent broker and its credential source
