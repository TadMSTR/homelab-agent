# Renovate

Renovate is a dependency update scanner that monitors Gitea repos for outdated
dependencies in config files, manifests, and language-specific package files (anything
that isn't Docker image versions — Dockhand handles those). On forge it runs as an hourly
PM2 cron job (`renovate-cron`) that starts the container, scans, and exits.

- **Image:** `renovate/renovate` (SHA-pinned in compose)
- **Compose:** `~/docker/renovate/docker-compose.yml`
- **Config:** `~/docker/renovate/config.js` (mounted `:ro`)
- **Cache:** `/opt/appdata/renovate/cache/`
- **PM2 job:** `renovate-cron` (ID 19, hourly schedule)
- **Network:** `forge-net`

## How It Runs

Renovate runs as a one-shot container (`restart: "no"`). PM2 cron (`renovate-cron`)
starts it hourly via `docker compose run`. The container scans discovered repos, opens
PRs for outdated dependencies, and exits. No persistent process — all state is in Gitea
PRs and the cache directory.

## Gitea Configuration

```js
// ~/docker/renovate/config.js
module.exports = {
  platform: 'gitea',
  endpoint: 'https://gitea.tadmstr.me',
  gitAuthor: 'Renovate Bot <renovate-bot@helmforge.me>',
  autodiscover: true,
  autodiscoverTopics: ['renovate'],   // only repos tagged 'renovate'
  onboarding: true,
  requireConfig: 'optional',
};
```

Renovate autodiscovers repos on `gitea.tadmstr.me` that have the `renovate` topic tag.
Currently tagged: `host-forge/stacks`.

## renovate-bot Service Account

A dedicated `renovate-bot` Gitea user holds the PAT used by Renovate. The PAT requires
exactly four scopes — missing any one causes an auth failure at startup with no clear
indication of which scope is absent:

| Scope | Required for |
|-------|-------------|
| `read:user` | Authenticating as renovate-bot |
| `write:repository` | Creating branches and PRs |
| `read:issue` | Reading existing issues/PRs |
| `write:issue` | Creating and updating PR comments |

The PAT value is stored in `~/docker/renovate/.env` (chmod 600) as `RENOVATE_TOKEN`.

## Cache Directory Ownership

`/opt/appdata/renovate/cache` must be owned by UID **12021** — the container's internal
ubuntu user. If the directory is owned by UID 1000 (ted), Renovate fails with permission
errors during the scan.

```bash
sudo chown -R 12021:12021 /opt/appdata/renovate/cache/
```

## Onboarding PR

On first run against a newly tagged repo, Renovate creates an onboarding PR
(`renovate/configure`) with a suggested `renovate.json` config. Renovate will not begin
scanning for real dependency updates until this PR is merged.

**Current state:** `renovate-cron` PM2 job is stopped. Enable it after the onboarding PR
in `host-forge/stacks` is reviewed and merged:

```bash
pm2 start renovate-cron
pm2 save
```

## host-forge/component-registry

A `host-forge/component-registry` repo was created in Gitea as part of this build with 5
initial component YAML stubs: dockhand, patchmon, renovate, swag, authentik. This repo
is separate from Renovate's scanning scope — it tracks service metadata for forge, not
dependency versions. Renovate will not open PRs against it (not tagged `renovate`).

## Security

From audit 2026-05-24:
- SHA-pinned image (L1, commit `5a77612`)
- Cache volume is the only writable mount; config is `:ro`

## Related Docs

- [forge-update-management-phase1.md](../phases/forge-update-management-phase1.md) — build narrative
