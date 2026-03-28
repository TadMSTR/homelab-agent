# Auto Mode Configuration

Claude Code's auto permission mode lets the agent approve routine tool calls without prompting — file reads, shell commands, MCP calls — based on classifier rules you define in `settings.json`. The result is a walk-away workflow: you start a session, the agent works through a build plan, and you check in when the dashboard or ntfy tells you something needs attention.

This doc covers the settings.json environment rules, the per-project SSH permissions for the helm-build agent, and a required patch to the CloudCLI SDK to make auto mode the default when launching sessions from the browser.

- **Global config:** `~/.claude/settings.json`
- **Per-project config:** `~/.claude/projects/<project>/settings.json`
- **CloudCLI patch:** `~/scripts/patch-cloudcli-auto-mode.sh`

## Why Auto Mode

Building with a multi-phase plan means dozens of tool calls — file reads, writes, npm installs, git operations, Docker commands. With the default permission mode, each one prompts for approval. That's right for exploratory work where you're present; it's friction when you've reviewed a build plan and just want it executed.

Auto mode with classifier rules is the middle ground. You define which categories of operations the agent can approve itself and which require a human. The agent proceeds on the first, pauses on the second.

The alternative — `skipPermissions` mode — bypasses all rules entirely. That's not useful here: the point is a safety net that approves routine operations, not one that approves everything.

## How It Works

Claude Code's permission system has three modes:

| Mode | Behavior |
|------|----------|
| Default | Every tool call prompts for approval |
| Auto | Tool calls matched against `allow`/`deny` rules in `settings.json`; unmatched calls prompt |
| skipPermissions | No prompts, no rules — everything allowed |

Auto mode reads `permissions.allow` and `permissions.deny` arrays. Rules are glob patterns matched against tool call signatures. The agent auto-approves anything matching an `allow` pattern that doesn't also match a `deny` pattern.

## Global Configuration

`~/.claude/settings.json` holds rules that apply across all projects:

```json
{
  "permissions": {
    "allow": [
      "Read(*)",
      "Write(~/.claude/**)",
      "Write(~/repos/personal/**)",
      "Bash(pm2 *)",
      "Bash(docker ps*)",
      "Bash(docker logs*)",
      "Bash(git status*)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "mcp__homelab-ops__read_file(*)",
      "mcp__homelab-ops__read_directory(*)",
      "mcp__homelab-ops__list_processes(*)",
      "mcp__graphiti__search_*",
      "WebFetch(https://ntfy.yourdomain/*)"
    ],
    "deny": [
      "Bash(rm -rf*)",
      "Bash(docker rm*)",
      "Bash(docker stop*)",
      "Bash(* --force*)",
      "Bash(sudo *)"
    ]
  }
}
```

These rules reflect a specific trust boundary: read operations and safe git/observability commands are auto-approved; destructive commands require human approval. Adjust the lists based on your own comfort level.

**Scoped ntfy access:** The `WebFetch` allow rule is scoped to the ntfy hostname and specific topic path. Without scoping, an agent in auto mode could fetch arbitrary external URLs automatically.

## Per-Project Configuration

The helm-build project needs additional permissions because the helm-ops MCP server executes shell commands on a remote machine via SSH. These are kept out of the global config intentionally — they're explicitly scoped to the project where they're needed:

`~/.claude/projects/helm-build/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__helm-ops__run_command(*)",
      "mcp__helm-ops__read_file(*)",
      "mcp__helm-ops__write_file(*)",
      "mcp__helm-ops__edit_file(*)"
    ]
  }
}
```

The helm-ops MCP executes shell commands on a separate host over SSH — wider blast radius than local operations. Scoping these to the helm-build project means they're only auto-approved in sessions explicitly targeting that workflow.

## CloudCLI SDK Patch

CloudCLI's session-start UI doesn't expose `permissionMode`. The SDK mapper (`server/claude-sdk.js`) supports the field, but the frontend never sends it — sessions always start in default mode.

A patch script adds a one-line default to the SDK mapper so sessions launched from CloudCLI start in auto mode:

```bash
# ~/scripts/patch-cloudcli-auto-mode.sh
# Adds an else clause to the permission mode mapper:
#   else { permissionMode = 'auto'; }
# Requires sudo (file lives in /usr/lib/node_modules/)
# Idempotent — checks whether the else clause is already present
```

Apply after installation or any CloudCLI update:

```bash
sudo bash ~/scripts/patch-cloudcli-auto-mode.sh && pm2 restart cloudcli
```

## Integration Points

Auto mode works alongside several other components:

- **Helm Dashboard** — the monitoring layer that makes walk-away operation practical. The dashboard shows what the agent is doing; the Live Updates panel shows which operations were auto-approved and which are waiting. See [helm-dashboard.md](helm-dashboard.md).
- **Agent manifests** — manifest `interaction_permissions` and workspace `AGENT_WORKSPACE.md` markers control filesystem path access; auto mode controls tool call categories. They're complementary. See [agent-workspace-scan.md](agent-workspace-scan.md).
- **NATS JetStream** — `tasks.approved` and `tasks.approval-requested` events show the approval disposition for dispatched tasks. See [nats-jetstream.md](nats-jetstream.md).
- **dep-update-check** — the dependency update checker flags CloudCLI updates, which should trigger re-running the SDK patch.

## Gotchas

**Re-apply the patch after every CloudCLI update.** `npm install -g @siteboon/claude-code-ui@latest` reinstalls from scratch and overwrites `claude-sdk.js`. The patch must be re-applied as a post-update step. The script is idempotent — safe to run multiple times.

**Auto mode is scoped to Claude Code CLI sessions.** It applies to sessions started from CloudCLI or the terminal (with `--permission-mode auto`). LibreChat agents run under different permission models — this configuration doesn't affect them.

**`skipPermissions` is not the same thing.** The CloudCLI UI has a "Skip Permissions" checkbox that enables `skipPermissions` mode, which bypasses the classifier entirely. Auto mode with rules is the intentional design; skip permissions is a different, less safe option. Don't confuse them.

**The `deny` list is a safety net, not an allowlist.** Auto mode approves anything matching `allow` that doesn't match `deny`. When adding new allow rules, make sure the pattern is narrow enough not to accidentally cover dangerous cases. Prefer specific tool names and path prefixes over broad wildcards.

## Standalone Value

The settings.json permission classifier is a Claude Code built-in — it doesn't require the rest of this stack. If you run Claude Code and want it to auto-approve file reads and specific safe commands without prompting, the global `settings.json` approach works independently of everything else here.

The CloudCLI SDK patch is specific to the `@siteboon/claude-code-ui` frontend — it won't be relevant if you use Claude Code only from the terminal. The underlying permission system is standard Claude Code settings.
