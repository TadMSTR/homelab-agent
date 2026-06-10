# Build: temporal-workflow-trigger-2026-06

**Date:** 2026-06-02
**Agent:** developer (build), sysadmin (deploy)
**Status:** Complete

---

## Summary

Wired the `temporal-build-worker` into the forge task dispatch pipeline. A new `task_type: workflow` in task-dispatcher.py routes submissions to Temporal via a bash/Python trigger chain, enabling durable workflow execution for build pipelines.

---

## What Was Built

### Task dispatcher workflow routing

Extended `task-dispatcher.py` with a `launch_temporal_workflow()` function that:
- Validates `workflow_type` against an allowlist (`BuildPipelineWorkflow`, `BuildPlanWorkflow`)
- Validates `plan_name` with regex `^[a-z0-9][a-z0-9-]*$`
- Generates workflow ID as `{plan_name}-{task_id[:8]}`
- Routes to `temporal-workflow-start.sh` with a 30-second timeout
- Falls back to `handle_routing_failure()` with exponential backoff on failure

The `temporal` virtual agent does not need a manifest entry — routing intercepts before manifest lookup.

### Trigger scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `temporal-workflow-start.sh` | `host-forge-scripts/scripts/` | Bash wrapper — sources Vault config, unsets sensitive env vars, delegates to Python |
| `temporal-start-workflow.py` | `host-forge-scripts/scripts/` | Python async client — fetches mTLS certs from Vault, starts Temporal workflow via SDK |

Security: the bash wrapper unsets `ANTHROPIC_API_KEY`, `GITEA_TOKEN`, `MATRIX_TOKEN`, `POSTGRES_PASSWORD` before spawning the Python process.

### Skill and CLAUDE.md updates

- `research-plan-queue` skill updated with `task_type: workflow` submission path
- Developer and sysadmin CLAUDE.md updated with Temporal task token handling instructions

---

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Python SDK over `docker exec` CLI | Temporal CLI not in server image; mTLS blocked CLI approach |
| Workflow type allowlist (M-01) | Prevents arbitrary workflow execution via task queue injection |
| Env var scoping in bash wrapper (L-01) | Minimize credential exposure to child process |
| Virtual agent `temporal` — no manifest | Routing intercept is simpler and avoids manifest maintenance |

---

## Security Audit

**Outcome:** PASS — 2 findings, both resolved.

| ID | Finding | Resolution |
|----|---------|------------|
| M-01 | No workflow_type validation — arbitrary workflow names accepted | Added allowlist: `BuildPipelineWorkflow`, `BuildPlanWorkflow` |
| L-01 | Env var scope — sensitive vars leaked to child process | Bash wrapper unsets 4 sensitive vars before exec |

---

## Flow

```
research-plan-queue (task_type: workflow)
  → task-queue-mcp
  → task-dispatcher: task_type=workflow → launch_temporal_workflow()
  → temporal-workflow-start.sh → temporal-start-workflow.py
  → Temporal: BuildPipelineWorkflow or BuildPlanWorkflow
  → worker writes task YAMLs → ~/.claude/task-queue/
  → agent executes phase → ~/scripts/temporal-complete
  → Temporal advances to next activity
```

---

## Related Docs

- [Temporal component](../components/temporal.md) — server stack details
- [temporal-build-worker README](https://github.com/TadMSTR/temporal-build-worker) — worker documentation
- Build plan: `~/.claude/comms/artifacts/build-plans/temporal-workflow-trigger-2026-06/plan.md`
- PR: host-forge-scripts#2 (merged)
