# vault-seal-watcher (retired 2026-10-26)

vault-seal-watcher was a bash script that polled HashiCorp Vault's health endpoint every
5 minutes and **unsealed Vault automatically** whenever it found it sealed. It existed
because the nightly Docker backup stopped and restarted the Vault container, which left it
sealed and blocked every agent that read its credentials from Vault.

## Retirement

It was retired with Vault itself, when the platform replaced Vault 1.19 with OpenBao 2.7.1
(see [vault.md](vault.md)). The new store's design goal was no unseal key on any host an
agent runs on, and auto-unseal can't meet it. To unseal without a human, the watcher had
to read the unseal key from a file. That key sat on NFS storage that the host, and so any
agent process on it, could read. Anything that backed up that share held a copy too.

Removed as part of the retirement:

- the auto-unseal helper script and the boot-time unseal systemd unit that ran it
- the watcher's 5-minute schedule
- the unseal key file on NFS, and the env file that held the Vault root token and unseal key
  side by side
- the Vault container, its data, and its copies in the nightly backups

The old Vault store was then destroyed, so the old root token and unseal key no longer
decrypt anything. That doesn't make the secrets inside it safe: they were imported into
OpenBao unchanged, and rotating them is a separate job.

The `scripts/vault-seal-watcher.sh` copy in this repo shows the old auto-unseal logic. It
is kept for reference only. Don't deploy it.

## Replacement: alert-only seal watcher

`openbao-seal-watcher.sh` replaces it, and it **never unseals**. OpenBao uses a manual
Shamir unseal (3 shares, threshold 2), and no share exists on the host, so the watcher has
nothing to unseal with. That's the point. The nightly-backup problem that led to
auto-unseal is now avoided a different way: OpenBao's state lives outside the appdata tree
that the backup job stops, and it's backed up with Raft snapshots instead.

| | vault-seal-watcher (retired) | openbao-seal-watcher (current) |
|---|---|---|
| On sealed | Ran the auto-unseal script with a key read from NFS | Sends a `critical` alert (Matrix alerts room, ntfy fallback), repeated every 6 h while sealed |
| On recovery | Logged OK | Sends one "cleared" message |
| Also reports | Unreachable (log line only) | `uninitialized` (Raft data missing: don't `init`, restore) and `unreachable`, both `critical` |
| Endpoint | `localhost:8200/v1/sys/health` | `127.0.0.1:8210/v1/sys/health?sealedcode=200&uninitcode=200&standbycode=200` |
| Schedule | PM2 cron, every 5 min | System cron every 5 min, under the Healthchecks wrapper |
| Exit code | n/a | 0 in every observed state (the ping measures that the watcher ran). 1 only if the watcher itself broke |

The current watcher, the unseal procedure, and the follow-up broker restarts are documented
in [vault.md](vault.md), under "Operations".

## What it was

- **Script:** `vault-seal-watcher.sh` (bash)
- **Schedule:** PM2 cron, every 5 minutes (`*/5 * * * *`), no listening port
- **Logic:** query `/v1/sys/health` for `sealed`. On `false`, log OK. On `true`, run the
  auto-unseal script and log the result. If unreachable, log a warning.
- **Dependencies:** Vault on port 8200, and an auto-unseal helper that read the unseal key
  from NFS and submitted it

## Related Docs

- [vault.md](vault.md): OpenBao, the store that replaced Vault, and its alert-only seal watcher
