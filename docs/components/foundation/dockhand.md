# Dockhand

Dockhand is a web-based Docker stack management UI. It shows running containers, compose
stacks, and image state, and it exposes compose operations (up, down, pull) through a browser
interface and a REST API. [dockhand-mcp](../mcp-servers/dockhand-mcp.md) wraps that API for
agents. Remote Docker hosts are added as further Dockhand *environments* through its Hawser
agent.

- **Image:** `fnsys/dockhand` (SHA-pinned to the index digest; v1.0.55 as of 2026-10-25)
- **URL:** `dockhand.example.com`
- **Port:** `127.0.0.1:7777` → container `3000`
- **Appdata:** `<appdata>/dockhand/`, which holds the SQLite DB, deploy logs, and
  Dockhand-internal stacks

## Volumes

| Mount | Purpose |
|-------|---------|
| `/var/run/docker.sock` | Docker API access |
| compose tree (read-only) | Compose file visibility |

The compose tree is mounted read-only. Dockhand can read compose files to show stack context
but cannot modify them. All compose edits go through the normal git-tracked workflow.

A stack whose `env_file` lives outside the mounted tree cannot be deployed through Dockhand.
The container cannot resolve the file. Use `docker compose` directly for those stacks.

## Access

Dockhand is on the shared proxy network and is reached through SWAG at
`dockhand.example.com`. Access control is at the proxy (forward auth). The application does
not password-protect each route itself. With `FEAT_API_DOCS=true`, `/openapi.json` and
`/api/docs` are served, and they sit behind the same forward auth. `/metrics` returns 401
unless `EXPORT_METRICS_PUBLIC` is set. Leave it unset.

## Docker Socket Access

Dockhand connects directly to `docker.sock`. A filtered socket proxy
(tecnativa/docker-socket-proxy) serves other services. Dockhand uses the raw socket because it
needs compose operations, not just read access. **Anything that can act as Dockhand is
root-equivalent on every host it manages.** That includes a holder of a live session or API
token.

## User Context

Dockhand runs as `user: "1000:1000"` with `group_add: "<docker-gid>"` (the host's `docker`
group GID) and `no-new-privileges`, so it can reach the socket without running as root.

## Known behaviour

Measured on v1.0.55:

- **Every compose-running stack action prints the stack's whole `.env` to Dockhand's
  stdout.** This covers start, stop, restart, deploy (with or without pull), and delete.
  Creating a stack with `start: false` does not print it. The cause is
  `parseEnvFileContent()`, which logs the raw file with no gate. It also logs a "Skipped
  lines" summary that repeats commented-out lines and multi-line continuations. This is the
  same code as v1.0.46, not a new regression. It applies whatever triggers the action: the
  UI, the scheduler, or the API. The dump goes to the container's stdout only. It is not
  stored in Dockhand's deploy history or its database.
  - Drop these lines in the log shipper before they reach Loki. Alloy can do this with a
    `stage.drop` on the dump's frame and on env-shaped lines, including `# KEY=` and
    dot/dash keys.
  - For stacks with secrets, prefer `docker compose` over Dockhand stack actions.
  - dockhand-mcp masks the dump in what it returns and requires an explicit acknowledgement
    on every `stack_action`.
- **Keep `<appdata>/dockhand` at mode 0700.** The DB (and its WAL/SHM files) holds live
  session tokens, and the container's umask is 0022, so Dockhand creates new files 0644. The
  parent directory's mode is the only control that stops a local user reading a token and
  presenting it to `127.0.0.1:7777`, which bypasses forward auth entirely. Re-apply the mode
  after any restore from an older backup archive.
- Dockhand writes the `.env` of an internal stack as 0644. The 0700 parent covers it.
- **v1.0.55 API additions** (+28 routes over v1.0.46, none removed): passkeys, container and
  stack tags, `containers/{id}/exec/run`, `containers/{id}/files/chown`, environment
  reports, `stack-stats`, and stack deploy history (`stacks/{name}/deploys`,
  `deploys/{runId}/log`). The deploy body is still `{pull, build, forceRecreate}` with no
  service parameter. `exec/run` and `files/chown` widen what a token holder can script. Do
  not wrap them in any agent tool without a HITL gate.
- The spec documents a `jobId` for stack start/stop, but with `Accept: application/json`
  the actions answer directly. Trust live behaviour over the spec here.
- `check_updates` flags `tag@sha256` pins whose tag has moved (since v1.0.54). It reports
  nothing for bare-digest pins.

## Upgrades

Dockhand cannot redeploy itself. Upgrade with `docker compose pull && docker compose up -d`
in its stack directory.

Before upgrading, take a consistent copy of the appdata directory with the container
stopped, or a filesystem snapshot of the volume. Keep the copy outside the appdata tree. The
v1.0.46 → v1.0.55 upgrade ran 7 DB migrations. Do not assume a downgrade across migrations is
safe. Rollback means re-pinning the old digest **and** restoring the data.

## Related Docs

- [swag.md](swag.md): reverse proxy providing HTTPS access
- [dockhand-mcp.md](../mcp-servers/dockhand-mcp.md): MCP wrapper over the Dockhand API
