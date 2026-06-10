#!/usr/bin/env python3
"""
doc-sync: Fetch, convert, and cache documentation for homelab services.

Saves chunked markdown files to ~/.claude/memory/docs/<service>/ so memsearch-watch
picks them up automatically. Agents can search with:
    memsearch search "SWAG authentik forward auth"

Config: ~/docs/doc-sync.yml
Cache:  ~/.claude/memory/docs/
Log:    ~/docs/doc-sync.log
"""

import os
import re
import sys
import json
import subprocess
import yaml
import logging
import requests
import html2text
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse

CONFIG_FILE  = Path.home() / "docs" / "doc-sync.yml"
CACHE_DIR    = Path.home() / ".claude" / "memory" / "docs"
MANIFEST     = Path.home() / "docs" / "cache-manifest.md"
LOG_FILE     = Path.home() / "docs" / "doc-sync.log"
STATE_FILE   = Path.home() / "docs" / "doc-sync-state.json"

# Forge OQP endpoint and auth key for memsearch indexing
MEMSEARCH_BIN = "/opt/venvs/memsearch/bin/memsearch"
OQP_BASE_URL  = "http://127.0.0.1:11435"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ]
)
log = logging.getLogger(__name__)

HEADERS = {"User-Agent": "forge-doc-sync/1.0 (homelab agent doc cache)"}
SESSION = requests.Session()
SESSION.headers.update(HEADERS)


# ── Fetch ─────────────────────────────────────────────────────────────────────

def fetch(url: str) -> str:
    """Fetch URL content. Returns raw text (markdown or HTML)."""
    r = SESSION.get(url, timeout=30)
    r.raise_for_status()
    return r.text


def to_markdown(content: str, url: str) -> str:
    """Convert HTML to markdown. Pass-through if already markdown."""
    if any(x in url for x in ["raw.githubusercontent.com", "llms.txt", ".md"]):
        return content

    h = html2text.HTML2Text()
    h.ignore_links = False
    h.ignore_images = True
    h.ignore_tables = False
    h.body_width = 0
    h.unicode_snob = True
    return h.handle(content)


# ── Chunking ──────────────────────────────────────────────────────────────────

def chunk_by_headings(content: str, min_size: int = 150, max_size: int = 4000) -> list[dict]:
    lines = content.splitlines()
    chunks = []
    current_title = "Overview"
    current_lines = []

    def flush(title, lines):
        body = "\n".join(lines).strip()
        if len(body) >= min_size:
            chunks.append({"title": title, "body": body})

    for line in lines:
        if re.match(r"^## ", line):
            flush(current_title, current_lines)
            current_title = line.lstrip("# ").strip()
            current_lines = [line]
        else:
            current_lines.append(line)

    flush(current_title, current_lines)

    result = []
    for chunk in chunks:
        if len(chunk["body"]) <= max_size:
            result.append(chunk)
            continue
        sub_title = chunk["title"]
        sub_lines = []
        for line in chunk["body"].splitlines():
            if re.match(r"^### ", line):
                body = "\n".join(sub_lines).strip()
                if len(body) >= min_size:
                    result.append({"title": sub_title, "body": body})
                sub_title = f"{chunk['title']} — {line.lstrip('# ').strip()}"
                sub_lines = [line]
            else:
                sub_lines.append(line)
        body = "\n".join(sub_lines).strip()
        if len(body) >= min_size:
            result.append({"title": sub_title, "body": body})

    return result


# ── Writing ───────────────────────────────────────────────────────────────────

def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60]


def write_chunks(service: str, topic: str, url: str, chunks: list[dict]) -> list[Path]:
    today      = date.today().isoformat()
    expires    = (date.today() + timedelta(days=90)).isoformat()
    out_dir    = CACHE_DIR / service
    out_dir.mkdir(parents=True, exist_ok=True)

    for old in out_dir.glob(f"{slug(topic)}-*.md"):
        old.unlink()

    written = []
    for i, chunk in enumerate(chunks):
        fname    = f"{slug(topic)}-{i:02d}-{slug(chunk['title'])}.md"
        fpath    = out_dir / fname
        frontmatter = (
            f"---\n"
            f"type: doc-cache\n"
            f"tier: working\n"
            f"service: {service}\n"
            f"topic: {topic}\n"
            f"section: {chunk['title']}\n"
            f"source_url: {url}\n"
            f"created: {today}\n"
            f"expires: {expires}\n"
            f"tags: [doc-cache, {service}, docs]\n"
            f"---\n\n"
        )
        fpath.write_text(frontmatter + chunk["body"])
        written.append(fpath)

    return written


# ── Manifest ──────────────────────────────────────────────────────────────────

def write_manifest(state: dict):
    today = date.today().isoformat()
    lines = [f"# Doc Cache Manifest\n\nLast updated: {today}\n"]
    for service, entries in sorted(state.items()):
        lines.append(f"\n## {service}\n")
        for entry in entries:
            lines.append(
                f"- **{entry['topic']}** — {entry['chunks']} chunks — "
                f"synced {entry['synced']} — `~/.claude/memory/docs/{service}/`  \n"
                f"  Source: {entry['url']}"
            )
    MANIFEST.write_text("\n".join(lines) + "\n")


# ── State ─────────────────────────────────────────────────────────────────────

def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, indent=2))


# ── Main ──────────────────────────────────────────────────────────────────────

def sync_entry(service: str, entry: dict) -> int:
    topic = entry["topic"]
    url   = entry["url"]

    log.info(f"[{service}] {topic} — {url}")
    try:
        raw      = fetch(url)
        md       = to_markdown(raw, url)
        chunks   = chunk_by_headings(md)
        if not chunks:
            log.warning(f"[{service}] {topic} — no chunks extracted, skipping")
            return 0
        written  = write_chunks(service, topic, url, chunks)
        log.info(f"[{service}] {topic} — {len(written)} chunks written")
        return len(written)
    except Exception as e:
        log.error(f"[{service}] {topic} — FAILED: {e}")
        return -1


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Sync documentation for homelab agents")
    parser.add_argument("--force",    action="store_true", help="Re-sync even if up to date")
    parser.add_argument("--service",  help="Only sync this service")
    parser.add_argument("--dry-run",  action="store_true", help="Show what would be synced")
    args = parser.parse_args()

    if not CONFIG_FILE.exists():
        log.error(f"Config not found: {CONFIG_FILE}")
        sys.exit(1)

    config = yaml.safe_load(CONFIG_FILE.read_text())
    state  = load_state()
    today  = date.today().isoformat()

    services = config.get("services", {})
    if args.service:
        if args.service not in services:
            log.error(f"Unknown service: {args.service}")
            sys.exit(1)
        services = {args.service: services[args.service]}

    total_synced = 0
    total_errors = 0

    for service, entries in services.items():
        if service not in state:
            state[service] = []

        for entry in entries:
            topic = entry["topic"]
            url   = entry["url"]

            if args.dry_run:
                print(f"  WOULD SYNC  [{service}] {topic}")
                continue

            n = sync_entry(service, entry)
            if n >= 0:
                total_synced += 1
                state[service] = [e for e in state[service] if e["topic"] != topic]
                state[service].append({"topic": topic, "url": url, "chunks": n, "synced": today})
            else:
                total_errors += 1

    if not args.dry_run:
        save_state(state)
        write_manifest(state)
        log.info(f"Sync complete. {total_synced} entries synced, {total_errors} errors.")

        if not args.service and total_synced > 0:
            log.info("Indexing docs cache into memsearch...")
            try:
                result = subprocess.run(
                    [MEMSEARCH_BIN, "index", str(CACHE_DIR)],
                    capture_output=True,
                    text=True,
                    timeout=900,
                )
                for line in result.stdout.splitlines():
                    if line.strip():
                        log.info("memsearch: %s", line)
                if result.returncode != 0:
                    log.warning("memsearch index exited %d", result.returncode)
            except subprocess.TimeoutExpired:
                msg = f"doc-sync-daily: memsearch index timed out after 900s ({total_synced} docs synced, index incomplete)"
                log.error(msg)
                subprocess.run(
                    [str(Path.home() / "scripts" / "send-matrix.sh"), "sysadmin", msg],
                    timeout=10,
                )

        if total_errors:
            sys.exit(1)


if __name__ == "__main__":
    main()
