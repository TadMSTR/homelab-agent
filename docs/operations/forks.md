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

**Version status:** fork baseline v0.4.14; upstream is one release ahead at v0.4.15 (non-security commits). Reconciliation is deferred, not yet scheduled.

## Checking for upstream updates

```bash
git -C <repo> fetch upstream --tags
git -C <repo> log <fork-branch>..upstream/main --oneline
```

Compare the new upstream commits against the fork's patch list above before merging — confirm none of forge's patches were superseded or conflict.

Note: `memsearch-mcp` is a separate, original forge MCP server with no upstream remote — it is not a fork and isn't covered here.
