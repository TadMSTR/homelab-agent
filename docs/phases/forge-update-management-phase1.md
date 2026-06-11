# Forge — Update Management Phase 1

**Completed:** 2026-05-24
**Snapshots:** pre-update-management (in `/.snapshots/`)

## What Was Built

Three-part build establishing forge's update management infrastructure:

1. **Dockhand compose visibility** — added a volume mount so Dockhand can read forge's Docker
   Compose files and display stack state in its UI.
2. **PatchPilot** — apt package tracking dashboard with an agent API. Authentik-protected UI
   at `patchpilot.helmforge.me`; agent port 8050 accessible LAN-only.
3. **Renovate** — dependency scanner for non-Docker dependencies (config files, manifests).
   Runs as an hourly PM2 cron (`renovate-cron`), autodiscovering Gitea repos tagged
   `renovate` on `gitea.tadmstr.me`.

Gitea infrastructure created alongside: `renovate-bot` service user with scoped PAT,
`renovate` topic tag applied to `host-forge/stacks`, and `host-forge/component-registry`
repo seeded with component YAML stubs for 5 services.

## Components Deployed

| Service | Purpose | URL / Port |
|---------|---------|------------|
| PatchPilot | apt package tracking, UI + agent API | `patchpilot.helmforge.me` (UI), `0.0.0.0:8050` (agent) |
| Renovate | non-Docker dependency scanning, PM2 cron | no UI — runs and exits |
| Dockhand (updated) | compose file visibility via new volume mount | existing service, remounted |

## Gitea Infrastructure

| Resource | Details |
|----------|---------|
| `renovate-bot` user | Service account for Renovate; PAT scoped to 4 permissions (see Renovate doc) |
| `renovate` topic tag | Applied to `host-forge/stacks`; Renovate autodiscovery uses this tag |
| `host-forge/component-registry` | New repo; 5 component YAML stubs (dockhand, patchpilot, renovate, swag, authentik) |

## Key Technical Findings

**Port 3002 occupied by firecrawl-api:** PatchPilot's UI is mapped to `127.0.0.1:3004:8443`
rather than the expected 3002. The 3004 assignment was recorded in the compose comment.

**Renovate PAT requires all four scopes:** `read:user`, `write:repository`, `read:issue`,
`write:issue`. Missing any single scope causes authentication failure at Renovate startup
without a clear error message about which scope is absent.

**Renovate cache UID:** `/opt/appdata/renovate/cache` must be owned by UID 12021 (the
container's internal ubuntu user). Ownership by UID 1000 causes permission errors during
the scan run.

**SWAG proxy confs are not hot-reloaded:** Adding a new `patchpilot.conf` to SWAG's
`proxy-confs/` does not take effect until `docker exec swag nginx -s reload` is run
explicitly. SWAG does not watch the directory for changes.

**Renovate onboarding PR:** On first run, Renovate creates an onboarding pull request in
each discovered repo (`renovate/configure`). The `renovate-cron` PM2 job should remain
stopped until the onboarding PR in `host-forge/stacks` is reviewed and merged. Scanning
begins only after the PR is merged.

## Security Audit Results

4 findings, all resolved.

| ID | Severity | Finding | Resolution |
|----|----------|---------|------------|
| M1 | Medium | Dockhand docker volume mounted rw — only needs ro | Changed to `:ro` (commit `5a77612`) |
| M2 | Medium | PatchPilot port 8050 on `0.0.0.0` — OPNsense rule unverified | UFW rule added: allow <lan-subnet> → port 8050; default deny confirmed |
| L1 | Low | PatchPilot + Renovate images not SHA-pinned | SHA-pinned in both compose files (commit `5a77612`) |
| L2 | Low | Dockhand missing `no-new-privileges:true` | Added to dockhand compose (commit `5a77612`) |

## Next Steps

- Merge Renovate onboarding PR in `host-forge/stacks` to activate scanning
- Enable `renovate-cron` PM2 job after onboarding PR is merged
- Populate `host-forge/component-registry` YAML stubs with full component metadata

## Related Docs

- [patchpilot.md](../components/patchpilot.md)
- [renovate.md](../components/cicd/renovate.md)
