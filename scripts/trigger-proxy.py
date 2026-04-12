#!/usr/bin/env python3
"""
trigger-proxy.py — Local HTTP proxy for firing claude.ai RemoteTriggers.

Runs on claudebox:5679. n8n (Docker) calls this via http://172.18.0.1:5679/fire-trigger
because the n8n container doesn't have direct access to Claude Code credentials or the
claude CLI. This service reads ~/.claude/.credentials.json, refreshes the token if
expired, and POSTs to the claude.ai trigger API on behalf of n8n.

Endpoints:
  POST /fire-trigger  body: {trigger_id, prompt, task_id}
  GET  /health        returns 200 {status: ok}

Log: /var/log/claudebox/trigger-proxy.log
"""

import json
import logging
import os
import secrets
import sys
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import requests

# --- Config ---
PORT = 5679
CREDENTIALS_FILE = Path.home() / ".claude" / ".credentials.json"
TRIGGER_MAP_FILE = Path.home() / ".claude" / "agent-manifests" / ".trigger-map.yml"
TRIGGER_API_BASE = "https://api.anthropic.com/v1/code/triggers"
OAUTH_REFRESH_URL = "https://claude.ai/api/auth/oauth/token"
LOG_FILE = "/var/log/claudebox/trigger-proxy.log"
TRIGGER_SECRET = os.environ.get("TRIGGER_PROXY_SECRET", "")

# --- Logging ---
os.makedirs("/var/log/claudebox", exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)


# --- Token management ---

def load_credentials() -> dict:
    """Load oauth credentials from ~/.claude/.credentials.json."""
    with open(CREDENTIALS_FILE) as f:
        data = json.load(f)
    return data.get("claudeAiOauth", {})


def save_credentials(creds: dict) -> None:
    """Write updated credentials back to file (atomic, permissions-safe)."""
    tmp = CREDENTIALS_FILE.with_suffix(".tmp")
    try:
        existing = {}
        if CREDENTIALS_FILE.exists():
            with open(CREDENTIALS_FILE) as f:
                existing = json.load(f)
        existing["claudeAiOauth"] = creds
        # Use os.open with explicit 0600 so rename preserves tight permissions.
        # open(tmp, "w") would inherit umask (0644) and downgrade credentials.json.
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(existing, f, indent=2)
        tmp.rename(CREDENTIALS_FILE)
    except Exception as e:
        log.warning(f"Failed to save refreshed credentials: {e}")
        tmp.unlink(missing_ok=True)


def is_token_expired(creds: dict) -> bool:
    """Return True if the access token is expired or within 60s of expiry."""
    expires_at_ms = creds.get("expiresAt", 0)
    # expiresAt is in milliseconds
    expires_at_s = expires_at_ms / 1000
    return time.time() >= (expires_at_s - 60)


def refresh_access_token(creds: dict) -> dict:
    """Attempt to refresh the OAuth access token. Returns updated creds or raises."""
    refresh_token = creds.get("refreshToken")
    if not refresh_token:
        raise RuntimeError("No refreshToken available")

    log.info("Access token expired — attempting refresh")
    resp = requests.post(
        OAUTH_REFRESH_URL,
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=15,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"Token refresh failed: {resp.status_code} {resp.text[:200]}")

    data = resp.json()
    creds["accessToken"] = data["access_token"]
    if "refresh_token" in data:
        creds["refreshToken"] = data["refresh_token"]
    # expires_in is seconds from now; convert to milliseconds epoch
    if "expires_in" in data:
        creds["expiresAt"] = int((time.time() + data["expires_in"]) * 1000)
    save_credentials(creds)
    log.info("Token refreshed and saved successfully")
    return creds


def get_valid_token() -> str:
    """Return a valid access token, refreshing if needed."""
    creds = load_credentials()
    if is_token_expired(creds):
        creds = refresh_access_token(creds)
    return creds["accessToken"]


# --- Trigger map lookup ---

def lookup_trigger_id(target_agent: str) -> str | None:
    """Look up trigger ID for an agent from .trigger-map.yml. Returns None if not found."""
    try:
        with open(TRIGGER_MAP_FILE) as f:
            for line in f:
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                colon = stripped.find(":")
                if colon == -1:
                    continue
                key = stripped[:colon].strip()
                val = stripped[colon + 1:].strip()
                if key == target_agent and val:
                    return val
    except Exception as e:
        log.warning(f"Failed to read trigger map: {e}")
    return None


# --- Trigger firing ---

def fire_trigger(trigger_id: str) -> dict:
    """Fire a RemoteTrigger via the Anthropic API. Returns response dict."""
    token = get_valid_token()
    url = f"{TRIGGER_API_BASE}/{trigger_id}/run"

    resp = requests.post(
        url,
        json=None,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "ccr-triggers-2026-01-30",
        },
        timeout=30,
    )

    if resp.status_code not in (200, 201, 202):
        raise RuntimeError(f"Trigger API returned {resp.status_code}: {resp.text[:300]}")

    try:
        return resp.json()
    except Exception:
        return {"status": "fired", "http_status": resp.status_code}


# --- HTTP handler ---

class TriggerProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.info(f"HTTP {self.address_string()} — {fmt % args}")

    def send_json(self, code: int, data: dict) -> None:
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"status": "ok", "time": datetime.now(timezone.utc).isoformat()})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/fire-trigger":
            self.send_json(404, {"error": "not found"})
            return

        # Shared-secret check — rejects requests from containers that don't know the secret
        if TRIGGER_SECRET:
            provided = self.headers.get("X-Trigger-Secret", "")
            if not secrets.compare_digest(provided, TRIGGER_SECRET):
                log.warning(f"Rejected unauthorized /fire-trigger from {self.address_string()}")
                self.send_json(401, {"error": "unauthorized"})
                return

        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 65536:
                self.send_json(413, {"error": "request too large"})
                return
            body = json.loads(self.rfile.read(length)) if length else {}
        except Exception as e:
            self.send_json(400, {"error": f"invalid JSON: {e}"})
            return

        trigger_id = body.get("trigger_id", "").strip()
        target_agent = body.get("target_agent", "").strip()

        # Resolve trigger_id from target_agent if not provided directly
        if not trigger_id and target_agent:
            trigger_id = lookup_trigger_id(target_agent) or ""
            if not trigger_id:
                msg = f"No trigger configured for agent: {target_agent}"
                log.warning(msg)
                self.send_json(404, {"error": msg, "target_agent": target_agent})
                return

        if not trigger_id:
            self.send_json(400, {"error": "trigger_id or target_agent is required"})
            return

        task_id = body.get("task_id")

        log.info(f"Firing trigger {trigger_id} (agent={target_agent or 'direct'}, task_id={task_id})")
        try:
            result = fire_trigger(trigger_id)
            log.info(f"Trigger {trigger_id} fired successfully")
            self.send_json(200, {"status": "fired", "trigger_id": trigger_id, "result": result})
        except Exception as e:
            log.error(f"Failed to fire trigger {trigger_id}: {e}")
            self.send_json(500, {"error": str(e), "trigger_id": trigger_id})


# --- Main ---

def main():
    log.info(f"=== trigger-proxy starting on port {PORT} ===")
    server = ThreadingHTTPServer(("172.18.0.1", PORT), TriggerProxyHandler)
    log.info(f"Listening on 0.0.0.0:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("trigger-proxy shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()
