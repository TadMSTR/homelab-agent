# code-server-mcp (retired 2026-10-28)

code-server-mcp was a FastMCP server that wrapped the [code-server](../cicd/code-server.md)
Docker container. It gave agents tools to health-check the container, generate deep-link URLs
for a repo folder, list installed VS Code extensions and install new ones.

## Retirement

Retired 2026-10-28. It had no real purpose: two tool calls over its whole deployed life, both
from the research agent, and the sysadmin agent never called it. Its deep-link tool only built
a URL pattern the operator can type directly.

Retiring it also removed a risky path. `list_extensions` and `install_extension` ran
`docker exec` into the code-server container, and `install_extension` had no human-in-the-loop
gate for the sysadmin agent. The research agent had it on a denylist.

The scoped-mcp module was removed from the research and sysadmin manifests, both brokers were
restarted before the upstream was stopped, and the PM2 app (`pm2 delete` + `pm2 save`), its
venv and its logs were deleted. It held no credentials, so nothing needed revoking. The public
repo, TadMSTR/code-server-mcp, is being archived.

The code-server container itself is unaffected and stays deployed. See
[code-server.md](../cicd/code-server.md).

## What it was

- **Repo:** TadMSTR/code-server-mcp (public)
- **Transport:** streamable-http on a loopback port, managed by PM2, proxied to agents through
  scoped-mcp
- **Config:** the code-server internal and public URLs, the container name and the
  `code-server` binary path inside the container. No secrets
- **Tools:** `health_check`, `open_folder_url` (allowlisted to the repos and docker
  directories), `list_extensions`, `install_extension` (marketplace ID, regex-validated)

**If you run it from the archived repo:** `install_extension` runs `docker exec` into the
container with no approval step. Put it behind a HITL gate or a `tool_denylist` in every
manifest that proxies the server.

## Related Docs

- [code-server.md](../cicd/code-server.md): the code-server container (still deployed)
