# AGENTS.md — homelab-agent

Public reference repository documenting a multi-agent AI homelab platform built on Claude Code. Covers the full three-layer architecture: dedicated host with MCP tool integrations, self-hosted Docker service stack, and multi-agent Claude Code engine with scoped memory and automated knowledge accumulation.

## Purpose

This repo has two audiences: humans learning to build a similar platform, and AI agents navigating the docs to assist with homelab tasks.

- **For humans:** Start with `README.md`, then `docs/getting-started.md`. Stop at any layer — each is independently useful.
- **For AI agents:** Load `index.md` for task-based doc routing. Do not load everything — use the context loading guide to load only what's relevant.

## Key Docs

- `README.md` — Architecture overview, layer descriptions, component tables
- `index.md` — Machine-readable nav index with topic/layer/task routing
- `docs/components/` — Per-component deep dives (one file per service)
- `docs/architecture.md` — Detailed system architecture and data flows
- `docs/getting-started.md` — Dependency-ordered setup with stopping points
- `mcp-servers/README.md` — MCP server reference, config patterns, adoption path

## Conventions

- **Sanitized for public use** — Internal IPs, domains, and credentials are replaced with placeholders or omitted. Component docs describe real architecture but use generic values.
- **Layer attribution** — Each component doc includes which layer it belongs to (Layer 1/2/3) and its dependencies.
- **One doc per component** — Avoid splitting a component across multiple files. Cross-references via links, not duplication.

## What Not to Change Without Discussion

- `index.md` — Machine-readable; format changes affect AI navigation. Keep the repo map and cross-reference table in sync with actual files.
- Sanitization policy — Public repo. No real IPs, domains, tokens, or personally identifying paths.
- Layer categorization — Misclassifying a component confuses the getting-started dependency order.
