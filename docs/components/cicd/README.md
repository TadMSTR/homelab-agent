# CI/CD & Dev Tools

Continuous integration, dependency and patch management, and development environments.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [woodpecker.md](woodpecker.md) | Woodpecker CI — pipeline execution for Gitea repos | 8000 |
| [temporal.md](temporal.md) | Temporal — durable workflow engine, retired 2026-10-25 | — |
| [renovate.md](renovate.md) | Automated dependency update scanning | — (scheduled) |
| [patchmon.md](patchmon.md) | Apt package tracking; fleet patching from its UI | 3005 |
| [code-server.md](code-server.md) | VS Code in the browser | 8443 |
| [cloudcli.md](cloudcli.md) | Browser-based Claude Code UI | 3001 |
| [owners-manual.md](owners-manual.md) | Auto-generated platform reference (MkDocs) | 8100 |

## Agent Integration

- **Woodpecker** runs CI pipelines triggered by Gitea pushes and PRs
- **Renovate** scans repos and opens PRs for dependency updates; the sysadmin agent reviews and merges them
- **PatchMon** has no agent integration: the operator runs fleet patching from its UI, and the sysadmin agent patches its own host with its apt-patch skill
