# nextcloud-mcp (retired 2026-10-28)

nextcloud-mcp was a FastMCP server that exposed Nextcloud operations as MCP tools: `occ` admin
commands run through `docker exec`, OCS Provisioning API calls for user and group management,
and WebDAV file and share operations. It ran as a PM2 process on a loopback streamable-http port
and was proxied to five agents through scoped-mcp.

## Retirement

Retired 2026-10-28. The [Nextcloud](apps/nextcloud.md) instance itself is unaffected and stays
deployed.

**Why:**

- **No recorded use.** No agent had made an `occ` or WebDAV call for weeks before the retirement.
- **The admin tools were broken.** The OCS and share tools fetched their admin credential from a
  secrets-store address that had moved, so they failed in production, and nobody noticed.
- **The `occ` tools needed no credential.** They ran `docker exec` into the Nextcloud container
  as a docker-group user. So revoking app passwords and losing the secrets store did not disarm
  them: they could still toggle security apps, change config, or mint a new app password for
  any user. The server was stopped before the manifests changed, because only stopping it
  closed that window.
- **The HTTP endpoint had no authentication.** It relied on a loopback-only bind, and that
  stopped being a sufficient boundary once the host began running processes under several
  isolated agent UIDs.

Earlier review findings pointed the same way. The admin password went on the `docker exec`
argv, where any local user can read it from `/proc/<pid>/cmdline`. `occ` error text echoed
arguments, secrets included.

**What was removed:**

- the scoped-mcp module, from all five agent manifests, along with the grant file;
- the PM2 app, its venv, its appdata, its logs and its secrets-store entries;
- every Nextcloud app password the server or the agents had used.

One of those app passwords turned out to be on the operator's own admin account, not on a
dedicated service account. An app password bypasses two-factor authentication. **If you deploy
an MCP server like this, give it a dedicated account, and list the app passwords on every
account when you retire it.**

The agents' Nextcloud accounts and their group were kept. The Agent Workspace External Storage
mount is applied to that group, so agents still share artifacts through web links. They no
longer have any Nextcloud API access.

**What replaced it:** the sysadmin agent runs the stack through an allowlisted `occ` wrapper
script, with a skill and a runbook. Writes need the operator's approval of the exact command
line. See [apps/nextcloud.md](apps/nextcloud.md#agent-access).

The public repo, TadMSTR/nextcloud-mcp, is being archived.

## What it was

- **Repo:** TadMSTR/nextcloud-mcp (public), v0.1.0
- **Transport:** streamable-http on a loopback port, managed by PM2
- **Tool groups:**

  | Group | Tools | Description |
  |-------|-------|-------------|
  | `occ-admin` | 17 | version, maintenance, apps, config, files, DB, full-text search, security, via `docker exec … occ` |
  | `ocs-provisioning` | 6 | users and groups, app password generation |
  | `files` | 8 | WebDAV list/get/put/move/delete, share create/list/delete |

- **Grants:** the sysadmin agent had all tools. Other agents had subsets of the `files` group,
  and the security agent had a few read-only `occ` tools. There was no authentication layer in
  the server: access control was entirely scoped-mcp grants.
- **Credentials:** an admin app password fetched from a secrets store, plus per-agent app
  passwords in env files.

## Related Docs

- [apps/nextcloud.md](apps/nextcloud.md): the Nextcloud stack (still deployed), agent workspace
  and agent access
