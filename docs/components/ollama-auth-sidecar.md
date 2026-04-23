# ollama-auth-sidecar

Minimal nginx sidecar that injects per-client Bearer auth for Ollama consumers that can't send `Authorization` headers natively. Designed for bare-Ollama users who need per-client credential isolation without a full proxy stack.

**Version:** 0.1.1 | **Source:** [TadMSTR/ollama-auth-sidecar](https://github.com/TadMSTR/ollama-auth-sidecar)

> **Status: Not yet deployed on claudebox.** Phase 7 (claudebox deployment) was deferred during initial build — memsearch-watch's use case is covered by the client injection port on ollama-queue-proxy. This doc is written for completeness.

## Why It Exists

Ollama's native auth is a single server-wide key: every client shares the same credential, there's no per-client attribution, and tools that can't send `Authorization: Bearer` headers are locked out. The sidecar addresses all three problems without adding queuing complexity.

Each consumer gets its own listen port and its own key. Clients that can't send auth headers point at the sidecar — the header is injected transparently. For users who also need priority queuing and failover, `ollama-queue-proxy` is the upgrade path.

## How It Works

A small Go config is rendered into per-service nginx `server` blocks at container startup. Each block:
1. Listens on a dedicated port
2. Validates the incoming request has no upstream auth header that would conflict
3. Injects `Authorization: Bearer <key>` before proxying to the configured upstream

Config is file-driven via `config.yaml` with `${ENV_VAR}` references in header values — keys never appear as literals in the config file. Startup fails fast if any referenced variable is unset.

## Config Model

```yaml
services:
  - name: openwebui
    listen: 11436
    upstream: http://ollama:11434
    timeout: 300s
    headers:
      Authorization: "Bearer ${OPENWEBUI_KEY}"
```

`listen` port range: 1024–65535. `timeout` applies to nginx `proxy_read_timeout` and `proxy_send_timeout`. Multiple services can share one container — each gets an independent server block.

## Deployment Modes

### Mode A — host networking (recommended)

Container runs with `network_mode: host`. `NGINX_BIND=127.0.0.1` keeps listen ports on loopback only. Host processes (PM2 services, scripts) reach them at `http://127.0.0.1:<port>`.

### Mode B — shared bridge network

Sidecar and consumer containers join a named Docker network. Consumers reach the sidecar by service name: `http://ollama-auth-sidecar:<port>`. Only services that need the sidecar should join the network.

## Security Notes

- Listen ports have no auth of their own — `NGINX_BIND=127.0.0.1` (the default) is what keeps them off the network
- Log format uses `$uri` (path only) rather than `$request_uri` — query strings are not logged
- JSON access logs redact `Authorization`, `Cookie`, and related headers by default
- Docker hardening defaults in both compose examples: `cap_drop: ALL`, `read_only: true`, tmpfs for nginx working dirs

## Relationship to ollama-queue-proxy

The two tools are positioned as a progression:

| Need | Tool |
|------|------|
| Per-client auth, no queuing | `ollama-auth-sidecar` |
| Auth + priority queuing + failover + embedding cache | `ollama-queue-proxy` |

`ollama-queue-proxy` v0.2.0 includes a client injection feature that covers the same "clients that can't send Bearer headers" use case at the proxy level. Users who start with the sidecar and outgrow it can migrate to the proxy without changing consumer config — same port convention.

Cross-links between the two READMEs are scoped to a future ollama-queue-proxy release.

## Full Reference

[TadMSTR/ollama-auth-sidecar](https://github.com/TadMSTR/ollama-auth-sidecar) — quick start, full config reference, key rotation runbook, deployment mode examples, and security policy.
