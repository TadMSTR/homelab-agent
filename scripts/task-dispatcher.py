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
_sys.path.insert(0, str(__import__('pathlib').Path.home() / "scripts"))
try:
    from agent_bus_client import log_event as bus_log
except ImportError:
    def bus_log(*a, **kw): pass  # no-op if client missing (safe degradation)

# --- Config ---
TASK_QUEUE_DIR = Path.home() / ".claude" / "task-queue"
ARCHIVE_DIR = TASK_QUEUE_DIR / "archive"
DEAD_LETTER_DIR = TASK_QUEUE_DIR / "dead-letters"
MANIFEST_DIR = Path.home() / ".claude" / "agent-manifests"
LOG_FILE = TASK_QUEUE_DIR / "dispatcher.log"
NTFY_URL = "https://ntfy.glitch42.com/claudebox"
N8N_WEBHOOK_URL = os.environ.get("N8N_WEBHOOK_URL", "")  # task-submitted webhook
N8N_APPROVED_WEBHOOK_URL = "http://localhost:5678/webhook/task-approved"

RISK_ORDER = {"low": 0, "medium": 1, "high": 2}
TERMINAL_STATES = {"completed", "failed"}
ALERT_INTERVAL_HOURS = 24
RETRY_BASE_SECONDS = 300  # 5 min base; backoff: 5m, 10m, 20m

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


# --- ntfy notification ---
def notify(title: str, body: str, tags: str = "task-queue", priority: str = "default") -> None:
    try:
        subprocess.run(
            ["curl", "-s",
             "-H", f"Title: {title}",
             "-H", f"Tags: {tags}",
             "-H", f"Priority: {priority}",
             "-d", body,
             NTFY_URL],
            timeout=10,
            capture_output=True,
        )
        log.info(f"ntfy sent: {title}")
    except Exception as e:
        log.warning(f"ntfy failed: {e}")


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


# --- n8n webhook (fire-and-forget) ---
def post_n8n_webhook(task: dict) -> None:
    """POST task to n8n webhook — fire-and-forget, no-op if URL not configured."""
    if not N8N_WEBHOOK_URL:
        return
    try:
        subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "",
             "-X", "POST", N8N_WEBHOOK_URL,
             "-H", "Content-Type: application/json",
             "-d", json.dumps({
                 "task_id": task.get("id"),
                 "summary": task.get("summary"),
                 "task_type": task.get("task_type"),
                 "target_agent": task.get("target_agent"),
                 "risk_level": task.get("risk_level", "low"),
                 "source_agent": task.get("submitted_by") or task.get("source_agent", ""),
                 "requires_approval": task.get("requires_approval"),
             })],
            timeout=10,
            capture_output=True,
        )
    except Exception:
        pass


# --- n8n approved webhook (fire-and-forget) ---
def post_n8n_approved_webhook(task: dict) -> None:
    """POST approved task to n8n task-approved webhook to fire RemoteTrigger."""
    try:
        subprocess.run(
            ["curl", "-s", "-o", "/dev/null",
             "-X", "POST", N8N_APPROVED_WEBHOOK_URL,
             "-H", "Content-Type: application/json",
             "-d", json.dumps({
                 "task_id": task.get("id"),
                 "summary": task.get("summary"),
                 "target_agent": task.get("target_agent"),
             })],
            timeout=10,
            capture_output=True,
        )
        log.info(f"Posted approved webhook for task {task.get('id')} → {task.get('target_agent')}")
    except Exception as e:
        log.warning(f"n8n approved webhook failed: {e}")


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
    # Write updated task to dead-letter location, then remove original
    atomic_write(dest, task)
    path.unlink(missing_ok=True)
    notify(
        f"[DEAD LETTER] {task.get('summary', path.stem)}",
        f"Task {task.get('id', path.stem)} permanently failed after max retries.\n"
        f"Reason: {reason}\nCheck ~/.claude/task-queue/dead-letters/",
        tags="task-queue,warning",
        priority="high",
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
            name = data.get("name")
            if name:
                manifests[name] = data
        except Exception as e:
            log.warning(f"Failed to load manifest {path}: {e}")
    return manifests


# --- Auto-routing for target_agent: auto ---
def find_agent(task: dict, manifests: dict) -> str | None:
    """Match task_type + scope to an agent. Returns agent name or None."""
    task_type = task.get("task_type")
    # Prefer claudebox-scoped agents for local tasks
    for name, m in manifests.items():
        caps = m.get("capabilities", [])
        hosts = m.get("scope", {}).get("hosts", [])
        if task_type in caps and ("all" in hosts or "claudebox" in hosts):
            return name
    # Fallback: any capable agent
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
        publish_nats("tasks.submitted", {"task_id": task.get("id"), "summary": task.get("summary"), "target_agent": task.get("target_agent"), "risk_level": task.get("risk_level", "low")})
        post_n8n_webhook(task)
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

        # Check interaction_permissions on target agent's manifest for source agent.
        # This centralizes approval policy in one place per agent and overrides
        # the generic max_auto_risk check when the source is explicitly listed.
        source_agent = task.get("submitted_by") or task.get("source_agent", "")
        interaction_perms = (manifest or {}).get("interaction_permissions", {})
        auto_approved_agents = interaction_perms.get("auto_approved", [])
        needs_approval_agents = interaction_perms.get("needs_approval", [])

        # bypass_approval: true is used by system components (e.g., rogue-agent lockdown tasks)
        bypass = task.get("bypass_approval", False)

        # Override requires_approval if explicitly set in task
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
            publish_nats("tasks.approval-requested", {"task_id": task.get("id"), "target_agent": target_agent, "risk_level": risk})
            bus_log("task.dispatched", source="dispatcher",
                    summary=f"Dispatched for approval: {task.get('summary', path.stem)}",
                    target=target_agent, artifact_path=str(path))
            log.info(f"{path.name}: → pending-approval (risk={risk}, max_auto={max_auto})")
            notify(
                f"[APPROVAL] {task.get('summary', path.stem)}",
                f"Source: {task.get('source_agent')} | Type: {task.get('task_type')} | Risk: {risk} | Agent: {target_agent}\n"
                f"Approve: task-approve {task.get('id', path.stem)}\nReject:  task-approve {task.get('id', path.stem)} --reject \"reason\"",
                tags="task-queue",
                priority="default",
            )
        else:
            task["status"] = "approved"
            append_history(task, "approved", "dispatcher",
                           f"Auto-approved: {approval_reason}")
            atomic_write(path, task)
            publish_nats("tasks.approved", {"task_id": task.get("id"), "target_agent": target_agent, "summary": task.get("summary")})
            post_n8n_approved_webhook(task)
            bus_log("task.approved", source="dispatcher",
                    summary=task.get("summary", path.stem),
                    target=target_agent, artifact_path=str(path))
            log.info(f"{path.name}: → approved (auto)")


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

        # Find when it was approved from history
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

            # Alert dedup: only re-alert after ALERT_INTERVAL_HOURS
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
            notify(
                f"[STALE] {task.get('summary', path.stem)}",
                f"Approved {age_hours}h ago, not yet claimed | Agent: {task.get('target_agent')} | ID: {task.get('id', path.stem)}",
                tags="task-queue,warning",
                priority="default",
            )

            # Update alert state
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
