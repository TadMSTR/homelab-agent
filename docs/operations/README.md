# docs/operations

Operational reference for running and maintaining the homelab-agent platform.

| File | Purpose |
|------|---------|
| `appdata-layout.md` | `/opt/appdata/` directory structure — where each service stores its persistent data |
| `runbooks.md` | Step-by-step runbooks for common operational procedures (agent recovery, memory pipeline, NATS health, Docker stack restarts) |
| `forks.md` | Forge's forked upstream dependencies — why each was forked, current patch list, and how to check for upstream updates |

For per-service operational details (restart commands, health checks, log locations), see the service's doc in `docs/components/`.
