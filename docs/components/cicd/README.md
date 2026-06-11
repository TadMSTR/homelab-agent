# CI/CD & Dev Tools

Continuous integration, workflow orchestration, dependency management, and development environments.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [woodpecker.md](woodpecker.md) | Woodpecker CI — pipeline execution for Gitea repos | 8000 |
| [temporal.md](temporal.md) | Temporal — durable workflow engine for agent build pipelines | 7233 |
| [renovate.md](renovate.md) | Automated dependency update scanning | — (scheduled) |
| [patchmon.md](patchmon.md) | Apt package tracking and patch approval | 3005 |
| [code-server.md](code-server.md) | VS Code in the browser | 8443 |
| [cloudcli.md](cloudcli.md) | Browser-based Claude Code UI | 3001 |
| [owners-manual.md](owners-manual.md) | Auto-generated platform reference (MkDocs) | 8100 |

## Agent Integration

- **Temporal** drives autonomous multi-step build pipelines — the temporal-build-worker PM2 process picks up workflows and executes them through agent sessions
- **Woodpecker** runs CI pipelines triggered by Gitea pushes and PRs
- **Renovate** scans repos and opens PRs for dependency updates; the sysadmin agent reviews and merges them
