# Appdata Layout Convention

Forge follows a two-directory convention for Docker stacks:

| Path | Contains |
|------|----------|
| `~/docker/<stack>/` | `docker-compose.yml`, `.env`, nginx confs — version-controlled in `host-forge/stacks` |
| `/opt/appdata/<stack>/<service>/` | Persistent data volumes — backed up by `docker-stack-backup.sh` |

Stack name is the same in both paths. Service name is the immediate subdirectory under the stack in `/opt/appdata/`.

## Examples

```
~/docker/observability/docker-compose.yml
/opt/appdata/observability/grafana/
/opt/appdata/observability/influxdb/
/opt/appdata/observability/loki/

~/docker/graphiti/docker-compose.yml
/opt/appdata/graphiti/neo4j/

~/docker/agent-platform/docker-compose.yml
/opt/appdata/agent-platform/dragonfly/
/opt/appdata/agent-platform/nats/
```

## Per-user Stacks

User stacks follow the same convention under a `users/` prefix:

```
~/docker/users/<username>/docker-compose.yml
/opt/appdata/users/<username>/dragonfly/
/opt/appdata/users/<username>/claude/
```

## Backup

`docker-stack-backup.sh` auto-discovers stacks from `~/docker/` and archives the matching `/opt/appdata/<stack>/` directory. The `users/` subtree requires a second pass — see Phase 5 documentation for the backup script extension.

## Migration Note

Before Phase 4, several services (grafana, influxdb, loki, neo4j) sat at the `/opt/appdata/` root rather than under a stack subdirectory. Phase 4 migrated them. All stacks deployed after Phase 4 land in the correct layout from day one.
