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

## memsearch — retired 2026-09-17, fork no longer actively synced

- Upstream: `zilliztech/memsearch`, remote `upstream`
- Fork: `TadMSTR/memsearch`, remote `origin`, branch `forge-main`
- Used to power forge's per-agent memory summarization pipeline; retired
  `memory-consolidation-2026-09` part 3 (vikunja#863) in favor of
  [scribe](../components/memory/scribe.md), which does not fork anything upstream

**Do not sync this fork further.** The plugin marketplace checkout it fed
(`~/.claude/plugins/marketplaces/memsearch-plugins`) no longer exists —
`plugin-drift-sentinel.py` has alerted `#alerts` on it every run of `memory-pipeline.sh`
since the retirement (`memsearch-plugins/declaration: expected
'TadMSTR/memsearch@forge-main', observed 'None@None'`). The source checkout at
`~/repos/personal/memsearch` is still present on disk but idle — a residual, not a live
dependency of anything. This section is kept for historical reference (what the fork
carried, why) rather than as an active maintenance entry; the patch list, version scheme
and last-synced state below describe the fork as it stood at retirement, not a target to
keep current.

Forge-specific patches carried at retirement (see `git log` on `forge-main` for the full list):
- `parse-transcript.sh` `isMeta`-turn skip in `format_turn()` — root-cause fix stopping template/skill text from leaking into `.memsearch/memory/*.md`
- Async spool stop hook re-ported onto v0.4.14
- `UserPromptSubmit` hook upgraded to inject memsearch results
- PATH fix for hook venv discovery

**Last synced:** 2026-08 (`memsearch-fork-upstream-sync-2026-08`) — `forge-main` merged
upstream/main through `d5809d7` (v0.4.17+3) at forge commit `5588877`, via
`TadMSTR/memsearch#9`. 28 upstream commits merged, 0 commits still lacking against
upstream at time of sync. No sync has run since, and none is planned.

**Version scheme (historical):** upstream's version number with a `-forge.N` suffix applied to
`plugin.json` and `.claude-plugin/marketplace.json` **only** — `pyproject.toml` and
`uv.lock` stayed bare. `N` reset to 1 whenever the upstream base version changed. Last
version: `0.4.17-forge.1`. The fork never cut its own git tags and had no `CHANGELOG.md`
in the repo or upstream — the plugin version bump in those two files *was* the release
mechanism.

**Historical note on verifying a plugin-cache refresh** (no longer applicable — the plugin
isn't installed): a `## Session HH:MM` heading in a fresh session transcript was not a
reliable refresh signal, since upstream commit `e657b05` (adopted in the 2026-08 sync)
moved that heading from an eager write in `session-start.sh` to a lazy write in `stop.sh`.
Kept for anyone reading old incident notes that reference it.

## Checking for upstream updates

```bash
git -C <repo> fetch upstream --tags
git -C <repo> log <fork-branch>..upstream/main --oneline
```

Compare the new upstream commits against the fork's patch list above before merging — confirm none of forge's patches were superseded or conflict. Only `claudecodeui` needs this now; `memsearch` above is retired and should not be synced.

Note: `memsearch-mcp` (also retired 2026-09-17, see [memsearch-mcp.md](../components/memory/memsearch-mcp.md)) was a separate, original forge MCP server with no upstream remote — it was never a fork and was never covered here.
