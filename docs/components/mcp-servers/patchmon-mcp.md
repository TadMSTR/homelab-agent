# patchmon-mcp (retired 2026-10-26)

patchmon-mcp was a FastMCP Python server wrapping the [PatchMon](../cicd/patchmon.md) REST
API. It gave agents read access to host patch state (enrolled hosts, installed and pending
packages, CVE reports, the agent task queue) and admin-API tools to preview, dry-run, approve
and trigger patch runs.

## Retirement

Retired 2026-10-26. It was effectively unused — six tool calls over its whole deployed life —
and patching had already moved elsewhere: fleet patching is done by the operator in the
PatchMon UI, and the sysadmin agent patches its own host with its apt-patch skill.

The scoped-mcp module was removed from the sysadmin agent's manifest, the launcher and venv
were deleted, and the PatchMon API credentials it used were rotated or revoked. The public
repo, TadMSTR/patchmon-mcp, is being archived.

The PatchMon server itself is unaffected and stays deployed — see
[patchmon.md](../cicd/patchmon.md).

## What it was

- **Repo:** TadMSTR/patchmon-mcp (public), last version 0.1.1
- **Transport:** stdio, launched as a scoped-mcp subprocess
- **Auth:** two credential sets — Basic Auth against PatchMon's read-only Integration API, and
  a cached, auto-refreshed JWT against the admin API
- **Tools:** `list_hosts`, `get_host`, `get_host_packages`, `get_host_stats`,
  `get_package_reports`, `get_agent_queue` (Integration API); `preview_patch_schedule`,
  `trigger_dry_run`, `get_patch_run`, `list_patch_runs`, `trigger_patch`,
  `approve_patch_run` (admin API)
- **Observability:** structlog JSON-L to stderr and a log file, with optional OTEL, InfluxDB
  and NATS extras. v0.1.1 fixed v0.1.0 writing logs to stdout, which corrupted the stdio
  JSON-RPC stream.

## Related Docs

- [patchmon.md](../cicd/patchmon.md) — PatchMon server (still deployed)
