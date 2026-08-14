# Forge Operational Forks

Forge maintains its own forks of two upstream open-source projects it depends on. Both forks exist to carry forge-specific patches that upstream hasn't accepted (or won't) — not for feature divergence. Forking (rather than patching in place at deploy time) keeps those patches under version control, reviewable, and safe to reapply after an upstream update.

## claudecodeui (CloudCLI UI)

- Upstream: `siteboon/claudecodeui`, remote `origin`
- Fork: `TadMSTR/claudecodeui`, remote `fork`
- Backs the CloudCLI operator UI

Forge-specific patches (see `git log origin/main..HEAD` for the current list):
- Keep MCP bearer tokens and credential literals out of CLI argv (SMCP-41)
- Permission-gated env passthrough for plugin subprocesses (manifest `env:<VAR>` + host-side `PLUGIN_ENV_ALLOWLIST`)
- Preserve the `cli.js` exec bit after `tsc` regenerates it

## memsearch

- Upstream: `zilliztech/memsearch`, remote `upstream`
- Fork: `TadMSTR/memsearch`, remote `origin`, branch `forge-main`
- Powers forge's per-agent memory summarization pipeline

Forge-specific patches (see `git log` on `forge-main` for the current list):
- `parse-transcript.sh` `isMeta`-turn skip in `format_turn()` — root-cause fix stopping template/skill text from leaking into `.memsearch/memory/*.md`
- Async spool stop hook re-ported onto v0.4.14
- `UserPromptSubmit` hook upgraded to inject memsearch results
- PATH fix for hook venv discovery

**Version status:** synced 2026-08 (`memsearch-fork-upstream-sync-2026-08`) — `forge-main` merged
upstream/main through `d5809d7` (v0.4.17+3) at forge commit `5588877`, via
`TadMSTR/memsearch#9`. 28 upstream commits merged, 0 commits still lacking against
upstream at time of sync.

**Version scheme:** take upstream's version number and apply a `-forge.N` suffix to
`plugin.json` and `.claude-plugin/marketplace.json` **only** — `pyproject.toml` and
`uv.lock` stay bare. Reset `N` to 1 whenever the upstream base version changes. Current:
`0.4.17-forge.1`. The fork does not cut its own git tags and there is no `CHANGELOG.md`
in the repo or upstream — the plugin version bump in those two files *is* the release
mechanism.

**Verifying a plugin-cache refresh:** do not check for a `## Session HH:MM` heading in a
fresh session transcript as a sign the cache refreshed — upstream commit `e657b05`
(adopted in the 2026-08 sync) moved that heading from an eager write in
`session-start.sh` to a lazy write in `stop.sh`, first written on the session's first
content-bearing Stop. A good refresh with no Stop yet looks identical to a broken one
under the old check. Verify instead with `installed_plugins.json` (expected version
present) plus `plugin-drift-sentinel.py` exiting 0 with no `cache_content` failure — see
[plugin-drift-sentinel.md](../components/plugin-drift-sentinel.md) for what that assertion
checks; not duplicated here.

## Checking for upstream updates

```bash
git -C <repo> fetch upstream --tags
git -C <repo> log <fork-branch>..upstream/main --oneline
```

Compare the new upstream commits against the fork's patch list above before merging — confirm none of forge's patches were superseded or conflict.

Note: `memsearch-mcp` is a separate, original forge MCP server with no upstream remote — it is not a fork and isn't covered here.
