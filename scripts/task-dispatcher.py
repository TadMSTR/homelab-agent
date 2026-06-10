#!/usr/bin/env python3
"""
task-dispatcher.py — Agent orchestration task queue dispatcher
Runs every 2 minutes via PM2 cron.

Logic:
  1. Process submitted tasks: route to agent, auto-approve or set pending-approval
     - Exponential backoff retry on routing failures (default 3 retries: 5m, 10m, 20m)
  2. Alert on stale approved tasks (unclaimed >24h, re-alert interval: 24h)
  3. Archive terminal tasks past ttl_days
  4. Log all transitions to dispatcher.log
"""

import glob
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import yaml

# agent-bus client — write path for Python scripts that cannot call MCP directly
import sys as _sys
_sys.path.insert(0, str(__import__('pathlib').Path.home() / "repos/personal/agent-bus"))
try:
    from agent_bus_client import log_event as bus_log
except ImportError:
    def bus_log(*a, **kw): pass  # no-op if client missing (safe degradation)

# --- Config ---
TASK_QUEUE_DIR = Path.home() / ".claude" / "task-queue"
ARCHIVE_DIR = TASK_QUEUE_DIR / "archive"
DEAD_LETTER_DIR = TASK_QUEUE_DIR / "dead-letters"
MANIFEST_DIR = Path.home() / ".claude" / "manifests"
LOG_FILE = TASK_QUEUE_DIR / "dispatcher.log"
MATRIX_MCP_URL = "http://127.0.0.1:8487/mcp"

RISK_ORDER = {"low": 0, "medium": 1, "high": 2}
TERMINAL_STATES = {"completed", "failed"}
ALERT_INTERVAL_HOURS = 24
RETRY_BASE_SECONDS = 300  # 5 min base; backoff: 5m, 10m, 20m

TEMPORAL_START_SCRIPT = Path.home() / "scripts" / "temporal-workflow-start.sh"

# Hardcoded whitelist — no user-supplied paths reach subprocess.Popen
AGENT_PROJECT_DIRS = {
    "sysadmin":  Path.home() / ".claude/projects/sysadmin",
    "developer": Path.home() / ".claude/projects/developer",
    "research":  Path.home() / ".claude/projects/research",
    "writer":    Path.home() / ".claude/projects/writer",
    "security":  Path.home() / ".claude/projects/security",
}

# --- Logging ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


# --- Atomic YAML write ---
def atomic_write(path: Path, data: dict) -> None:
    """Write YAML to a tmp file then mv into place to prevent race conditions."""
    tmp = path.with_suffix(".tmp")
    try:
        fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        tmp.rename(path)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise


def load_yaml(path: Path) -> dict:
    with open(path) as f:
        return yaml.safe_load(f) or {}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# --- History append ---
def append_history(task: dict, status: str, actor: str, note: str = "") -> None:
    entry = {"timestamp": now_iso(), "status": status, "actor": actor}
    if note:
        entry["note"] = note
    task.setdefault("history", []).append(entry)


# --- Retry eligibility check ---
def is_eligible(task: dict) -> bool:
    """Return True if the task is eligible for routing (retry window has passed)."""
    next_retry = task.get("retry_policy", {}).get("next_retry_at")
    if next_retry is None:
        return True
    return datetime.now(timezone.utc) >= datetime.fromisoformat(next_retry)


# --- Routing failure handler with exponential backoff ---
def handle_routing_failure(path: Path, task: dict, reason: str) -> None:
    """Handle a task routing failure with exponential backoff retry."""
    policy = task.setdefault("retry_policy", {})
    retry_count = policy.get("retry_count", 0)
    max_retries = policy.get("max_retries", 3)

    policy["last_failure_reason"] = reason
    append_history(task, "routing-failed", "dispatcher", reason)

    if retry_count < max_retries:
        backoff_seconds = RETRY_BASE_SECONDS * (2 ** retry_count)
        policy["retry_count"] = retry_count + 1
        policy["next_retry_at"] = (
            datetime.now(timezone.utc) + timedelta(seconds=backoff_seconds)
        ).isoformat()
        task["status"] = "submitted"  # re-enter the queue
        atomic_write(path, task)
        bus_log("task.routing-failed", source="dispatcher",
                summary=f"Routing failed (retry {retry_count + 1}/{max_retries}): {reason}",
                target=task.get("target_agent"), artifact_path=str(path))
        log.info(
            f"{path.name}: routing failed ({reason}); "
            f"retry {retry_count + 1}/{max_retries} in {backoff_seconds // 60}m"
        )
    else:
        task["status"] = "failed"
        publish_nats("tasks.failed", {"task_id": task.get("id"), "summary": task.get("summary")})
        bus_log("task.failed", source="dispatcher",
                summary=f"Task failed (exhausted {max_retries} retries): {reason}",
                target=task.get("target_agent"), artifact_path=str(path))
        log.warning(f"{path.name}: exhausted {max_retries} retries: {reason}")
        move_to_dead_letter(path, task, reason)


# --- Matrix notification (via matrix-mcp HTTP endpoint) ---
def matrix_notify(room: str, title: str, body: str) -> None:
    """Post a notification to a named Matrix room via matrix-mcp."""
    try:
        payload = json.dumps({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "send_matrix_message",
                "arguments": {
                    "room_name": room,
                    "message": f"**{title}**\n{body}"
                }
            },
            "id": 1
        })
        subprocess.run(
            ["curl", "-s", "-X", "POST", MATRIX_MCP_URL,
             "-H", "Content-Type: application/json",
             "-d", payload],
            timeout=10,
            capture_output=True,
        )
        log.info(f"matrix_notify sent to #{room}: {title}")
    except Exception as e:
        log.warning(f"matrix_notify failed: {e}")


# --- NATS publish (fire-and-forget) ---
def publish_nats(subject: str, payload: dict) -> None:
    """Fire-and-forget NATS publish — never blocks the dispatcher."""
    try:
        subprocess.run(
            ["nats", "pub", "--server", "nats://localhost:4222", subject, json.dumps(payload)],
            timeout=5,
            capture_output=True,
        )
    except Exception:
        pass


# --- Headless agent launch ---
def launch_agent_headless(task: dict) -> None:
    """Launch the target agent headlessly via claude -p."""
    target = task.get("target_agent", "")
    project_dir = AGENT_PROJECT_DIRS.get(target)
    if project_dir is None:
        handle_routing_failure(
            Path(TASK_QUEUE_DIR / f"{task.get('id', 'unknown')}.yml"),
            task,
            f"Unknown agent for headless launch: {target!r}"
        )
        return
    if not project_dir.is_dir():
        handle_routing_failure(
            Path(TASK_QUEUE_DIR / f"{task.get('id', 'unknown')}.yml"),
            task,
            f"Project dir missing: {project_dir}"
        )
        return
    task_id = task.get("id", "unknown")
    if not re.fullmatch(r'[0-9a-f\-]{36}', task_id):
        task_id = "invalid-id"
    # SECURITY[resolved]: summary removed from prompt to prevent prompt injection.
    # Agent discovers task content via task-queue tools using task_id. Audit: 2026-05-29/forge-build-workflow-infra-2026-05.
    log_file = Path.home() / ".pm2" / "logs" / f"agent-launch-{target}-{task_id[:8]}.log"
    with open(log_file, "a") as lf:
        proc = subprocess.Popen(
            ["claude", "-p",
             "--dangerously-skip-permissions",
             f"You have a pending task (id={task_id}). "
             f"Check your task queue and proceed."],
            cwd=str(project_dir),
            stdout=lf,
            stderr=lf,
        )
    log.info(f"Headless launch: {target} (pid={proc.pid}) task={task_id[:8]}")


# --- Temporal workflow launch ---
# SECURITY[control]: workflow_type allowlisted before subprocess invocation.
# Audit: 2026-06-02/temporal-workflow-trigger-2026-06.
ALLOWED_WORKFLOW_TYPES = {"BuildPipelineWorkflow", "BuildPlanWorkflow"}


def launch_temporal_workflow(path: Path, task: dict) -> bool:
    """Submit a Temporal workflow for a task_type=workflow task.

    Returns True on success, False on failure (failure already handled via
    handle_routing_failure before returning).
    """
    payload = task.get("payload", {})
    workflow_type = payload.get("workflow_type", "BuildPipelineWorkflow")
    if workflow_type not in ALLOWED_WORKFLOW_TYPES:
        handle_routing_failure(
            path, task,
            f"Unknown workflow_type: {workflow_type!r} (allowed: {ALLOWED_WORKFLOW_TYPES})"
        )
        return False
    task_id = task.get("id", "unknown")
    if not re.fullmatch(r'[0-9a-f\-]{36}', task_id):
        task_id = "invalid-id"
    plan_name = payload.get("plan_name", "")
    if not re.fullmatch(r'[a-z0-9][a-z0-9\-]*', plan_name):
        handle_routing_failure(
            path, task,
            f"Invalid plan_name for workflow submission: {plan_name!r}"
        )
        return False
    workflow_id = f"{plan_name}-{task_id[:8]}"
    input_json = json.dumps({
        "plan_name": plan_name,
        **{k: v for k, v in payload.items()
           if k not in ("workflow_type", "plan_name", "task_token")}
    })
    log_file = Path.home() / ".pm2" / "logs" / f"temporal-start-{task_id[:8]}.log"
    try:
        with open(log_file, "a") as lf:
            result = subprocess.run(
                [str(TEMPORAL_START_SCRIPT), workflow_type, workflow_id, input_json],
                stdout=lf, stderr=lf, timeout=30
            )
        if result.returncode != 0:
            handle_routing_failure(
                path, task,
                f"temporal-workflow-start.sh exited {result.returncode}"
            )
            return False
        log.info(f"Temporal workflow started: {workflow_type} id={workflow_id} task={task_id[:8]}")
        return True
    except subprocess.TimeoutExpired:
        handle_routing_failure(
            path, task,
            "temporal-workflow-start.sh timed out (30s)"
        )
        return False


# --- Dead-letter queue ---
def move_to_dead_letter(path: Path, task: dict, reason: str) -> None:
    """Move a permanently failed task to the dead-letters directory and alert."""
    DEAD_LETTER_DIR.mkdir(exist_ok=True)
    task["failed_reason"] = {
        "timestamp": now_iso(),
        "reason": reason,
        "retry_count": task.get("retry_policy", {}).get("retry_count", 0),
    }
    dest = DEAD_LETTER_DIR / path.name
    atomic_write(dest, task)
    path.unlink(missing_ok=True)
    matrix_notify(
        "forge",
        f"[dead-letter] {task.get('summary', path.stem)}",
        f"Task {task.get('id', path.stem)} failed after max retries.\nReason: {reason}",
    )
    log.warning(f"{path.name}: moved to dead-letters (reason={reason})")


# --- Load manifests ---
def load_manifests() -> dict:
    """Returns dict keyed by agent name."""
    manifests = {}
    for path in MANIFEST_DIR.glob("*.yml"):
        if path.name.startswith(".") or path.stem == "example-manifest":
            continue
        try:
            data = load_yaml(path)
            name = data.get("agent_type") or data.get("name")
            if name:
                manifests[name] = data
        except Exception as e:
            log.warning(f"Failed to load manifest {path}: {e}")
    return manifests


# --- Auto-routing for target_agent: auto ---
def find_agent(task: dict, manifests: dict) -> str | None:
    """Match task_type + scope to an agent. Returns agent name or None."""
    task_type = task.get("task_type")
    for name, m in manifests.items():
        caps = m.get("capabilities", [])
        hosts = m.get("scope", {}).get("hosts", [])
        if task_type in caps and ("all" in hosts or "forge" in hosts):
            return name
    for name, m in manifests.items():
        if task_type in m.get("capabilities", []):
            return name
    return None


# --- Phase 1: Process submitted tasks ---
def process_submitted(manifests: dict) -> None:
    for path in sorted(TASK_QUEUE_DIR.glob("*.yml")):
        if path.name.startswith("."):
            continue
        try:
            task = load_yaml(path)
        except Exception as e:
            log.warning(f"Failed to parse {path.name}: {e}")
            continue

        if task.get("status") != "submitted":
            continue

        if not is_eligible(task):
            log.debug(f"{path.name}: retry not yet eligible, skipping")
            continue

        log.info(f"Processing submitted task: {path.name}")
        publish_nats("tasks.submitted", {
            "task_id": task.get("id"),
            "summary": task.get("summary"),
            "target_agent": task.get("target_agent"),
            "risk_level": task.get("risk_level", "low"),
        })
        target = task.get("target_agent", "auto")

        # Resolve auto-routing
        if target == "auto":
            resolved = find_agent(task, manifests)
            if resolved is None:
                msg = f"No agent found for task_type={task.get('task_type')}"
                log.warning(f"{path.name}: {msg}")
                handle_routing_failure(path, task, msg)
                continue
            task["target_agent"] = resolved
            log.info(f"{path.name}: auto-routed to {resolved}")

        target_agent = task["target_agent"]
        manifest = manifests.get(target_agent)
        risk = task.get("risk_level", "low")

        # Determine max auto risk from manifest
        if manifest:
            max_auto = manifest.get("max_auto_risk", "low")
        else:
            max_auto = "low"
            log.warning(f"{path.name}: no manifest for agent '{target_agent}', defaulting to low")

        source_agent = task.get("submitted_by") or task.get("source_agent", "")
        interaction_perms = (manifest or {}).get("interaction_permissions", {})
        auto_approved_agents = interaction_perms.get("auto_approved", [])
        needs_approval_agents = interaction_perms.get("needs_approval", [])

        bypass = task.get("bypass_approval", False)
        explicit_approval = task.get("requires_approval")

        if bypass:
            needs_approval = False
            approval_reason = "bypass_approval=true (system override)"
        elif explicit_approval is True:
            needs_approval = True
            approval_reason = "requires_approval=true (explicit)"
        elif explicit_approval is False:
            needs_approval = False
            approval_reason = "requires_approval=false (explicit)"
        elif source_agent and source_agent in auto_approved_agents:
            needs_approval = False
            approval_reason = f"source '{source_agent}' in target manifest auto_approved list"
        elif source_agent and source_agent in needs_approval_agents:
            needs_approval = True
            approval_reason = f"source '{source_agent}' in target manifest needs_approval list"
        else:
            needs_approval = RISK_ORDER.get(risk, 0) > RISK_ORDER.get(max_auto, 0)
            approval_reason = f"risk={risk} vs max_auto_risk={max_auto} (fallback)"

        log.info(f"{path.name}: approval={needs_approval} — {approval_reason}")

        if needs_approval:
            task["status"] = "pending-approval"
            append_history(task, "pending-approval", "dispatcher",
                           f"Needs approval: {approval_reason}")
            atomic_write(path, task)
            publish_nats("tasks.approval-requested", {
                "task_id": task.get("id"),
                "target_agent": target_agent,
                "risk_level": risk,
            })
            bus_log("task.dispatched", source="dispatcher",
                    summary=f"Dispatched for approval: {task.get('summary', path.stem)}",
                    target=target_agent, artifact_path=str(path))
            log.info(f"{path.name}: → pending-approval (risk={risk}, max_auto={max_auto})")
            matrix_notify(
                "approvals",
                f"[APPROVAL NEEDED] {task.get('summary', path.stem)}",
                f"Source: {task.get('source_agent')} | Type: {task.get('task_type')} | Risk: {risk} | Agent: {target_agent}\n"
                f"`task-approve {task.get('id', path.stem)}`",
            )
            matrix_notify(
                "forge",
                f"[pending-approval] {task.get('summary', path.stem)}",
                f"Agent: {target_agent} | Risk: {risk}",
            )
        else:
            task["status"] = "approved"
            append_history(task, "approved", "dispatcher",
                           f"Auto-approved: {approval_reason}")
            atomic_write(path, task)
            publish_nats("tasks.approved", {
                "task_id": task.get("id"),
                "target_agent": target_agent,
                "summary": task.get("summary"),
            })
            if task.get("task_type") == "workflow":
                if launch_temporal_workflow(path, task):
                    task["status"] = "in-progress"
                    append_history(task, "in-progress", "dispatcher",
                                   "Temporal workflow submitted")
                    atomic_write(path, task)
                    bus_log("task.workflow_started", source="dispatcher",
                            summary=f"Temporal workflow started: {task.get('summary', path.stem)}",
                            target=target_agent, artifact_path=str(path))
                    log.info(f"{path.name}: → in-progress (temporal workflow)")
                    matrix_notify(
                        "forge",
                        f"[temporal] {task.get('summary', path.stem)}",
                        f"Workflow: {task.get('payload', {}).get('workflow_type', 'BuildPipelineWorkflow')}"
                        f" | plan: {task.get('payload', {}).get('plan_name', '?')}",
                    )
                continue
            elif task.get("task_type") == "audit" and target_agent == "security":
                payload = task.get("payload", {})
                request_path_str = payload.get("request", "") or next(
                    (r for r in (payload.get("context_refs") or []) if "audit-requests" in r), ""
                )
                build_name = (
                    Path(request_path_str).parent.name
                    if request_path_str else
                    next(iter(re.findall(r'audit-requests/([a-zA-Z0-9_\-]+)', payload.get("description", ""))), "unknown")
                )
                # SECURITY[resolved]: reject "unknown" build_name to prevent silent non-functional audit launches.
                # Audit: 2026-05-29/forge-build-workflow-infra-2026-05.
                if build_name == "unknown" or not re.fullmatch(r'[a-zA-Z0-9_\-]+', build_name):
                    handle_routing_failure(path, task, f"Invalid or missing build_name in payload: {build_name!r}")
                    continue
                audit_root = (Path.home() / ".claude/comms/artifacts/audit-requests").resolve()
                request_path = Path(request_path_str).expanduser().resolve() if request_path_str else (
                    audit_root / build_name / "request.md"
                )
                try:
                    request_path.relative_to(audit_root)
                except ValueError:
                    handle_routing_failure(path, task, f"request_path outside audit-requests: {request_path}")
                    continue
                # SECURITY[resolved]: verify request_path exists on disk before launching.
                # Audit: 2026-05-29/forge-build-workflow-infra-2026-05.
                if not request_path.exists():
                    handle_routing_failure(path, task, f"request_path does not exist: {request_path}")
                    continue
                security_project_dir = Path.home() / ".claude" / "projects" / "security"
                audit_log = Path.home() / ".pm2" / "logs" / f"security-audit-{build_name}.log"
                with open(audit_log, "a") as audit_log_fh:
                    proc = subprocess.Popen(
                        ["claude", "-p",
                         "--dangerously-skip-permissions",
                         f"Run security audit for build: {build_name}. "
                         f"Request at: {request_path}"],
                        cwd=str(security_project_dir),
                        stdout=audit_log_fh,
                        stderr=audit_log_fh,
                    )
                log.info(f"{path.name}: headless audit launched for {build_name} (pid={proc.pid}) log={audit_log}")
            else:
                workflow_mode = task.get("workflow_mode", "semi-auto")
                if workflow_mode == "auto":
                    # auto mode: headless launch if auto_start or auto mode implies it
                    log.info(f"{path.name}: workflow_mode=auto — launching headless")
                    launch_agent_headless(task)
                else:
                    # semi-auto mode (default): queue for operator pickup, notify agent room
                    log.info(f"{path.name}: workflow_mode=semi-auto — queued for operator pickup")
                    task_id = task.get("id", path.stem)
                    # SECURITY[accepted]: summary interpolated into Matrix notification title — Markdown injection possible
                    # but not HTML/JSON injection. Trust model: internal agents not adversarial. Pre-existing pattern.
                    # Audit: 2026-06-08/workflow-qol-2026-06 INFO-1.
                    summary = task.get("summary", path.stem)
                    source = task.get("source_agent", "unknown")
                    matrix_notify(
                        target_agent,
                        f"[task ready] {summary}",
                        f"Task ID: {task_id}\nFrom: {source} | Risk: {risk}\n"
                        f'Resume: Check task queue (id={task_id}) and run shared-build-review.',
                    )
            bus_log("task.approved", source="dispatcher",
                    summary=task.get("summary", path.stem),
                    target=target_agent, artifact_path=str(path))
            log.info(f"{path.name}: → approved (auto)")
            matrix_notify(
                "forge",
                f"[auto-approved] {task.get('summary', path.stem)}",
                f"Agent: {target_agent} | Risk: {risk} | Mode: {task.get('workflow_mode', 'semi-auto')}",
            )


# --- Phase 2: Alert on stale approved tasks ---
def alert_stale_approved() -> None:
    threshold = datetime.now(timezone.utc) - timedelta(hours=24)
    for path in sorted(TASK_QUEUE_DIR.glob("*.yml")):
        if path.name.startswith("."):
            continue
        try:
            task = load_yaml(path)
        except Exception:
            continue

        if task.get("status") != "approved":
            continue

        approved_at = None
        for entry in reversed(task.get("history", [])):
            if entry.get("status") == "approved":
                ts_str = entry.get("timestamp", "")
                try:
                    approved_at = datetime.fromisoformat(ts_str)
                except ValueError:
                    pass
                break

        if approved_at and approved_at < threshold:
            age_hours = int((datetime.now(timezone.utc) - approved_at).total_seconds() / 3600)

            alert_state = task.get("alert_state", {})
            last_alerted = alert_state.get("last_alerted_at")
            should_alert = (
                last_alerted is None or
                (datetime.now(timezone.utc) - datetime.fromisoformat(last_alerted)).total_seconds()
                > ALERT_INTERVAL_HOURS * 3600
            )

            if not should_alert:
                log.debug(f"{path.name}: stale alert suppressed (last sent {last_alerted})")
                continue

            log.info(f"{path.name}: stale approved task ({age_hours}h unclaimed), sending alert")
            matrix_notify(
                "forge",
                f"[stale] {task.get('summary', path.stem)}",
                f"Approved {age_hours}h ago, unclaimed | Agent: {task.get('target_agent')}",
            )

            now_str = now_iso()
            task.setdefault("alert_state", {})
            if task["alert_state"].get("first_alerted_at") is None:
                task["alert_state"]["first_alerted_at"] = now_str
            task["alert_state"]["last_alerted_at"] = now_str
            task["alert_state"]["alert_count"] = task["alert_state"].get("alert_count", 0) + 1
            atomic_write(path, task)


# --- Phase 3: Archive terminal tasks past TTL ---
def archive_expired() -> None:
    ARCHIVE_DIR.mkdir(exist_ok=True)
    now = datetime.now(timezone.utc)
    for path in sorted(TASK_QUEUE_DIR.glob("*.yml")):
        if path.name.startswith("."):
            continue
        try:
            task = load_yaml(path)
        except Exception:
            continue

        if task.get("status") not in TERMINAL_STATES:
            continue

        ttl_days = task.get("ttl_days", 30)
        created_str = task.get("created", "")
        try:
            created = datetime.fromisoformat(str(created_str))
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
        except (ValueError, TypeError):
            continue

        age_days = (now - created).days
        if age_days >= ttl_days:
            dest = ARCHIVE_DIR / path.name
            path.rename(dest)
            log.info(f"Archived {path.name} (age={age_days}d, ttl={ttl_days}d, status={task['status']})")


# --- Main ---
def main():
    log.info("=== task-dispatcher run start ===")
    manifests = load_manifests()
    log.info(f"Loaded {len(manifests)} agent manifests: {list(manifests.keys())}")

    process_submitted(manifests)
    alert_stale_approved()
    archive_expired()

    log.info("=== task-dispatcher run complete ===")


if __name__ == "__main__":
    main()
