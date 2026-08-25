# Agent Infrastructure — Dispatch, Communication & Coordination

The services that make the multi-agent engine work: tool scoping, inter-agent messaging, task routing, and session management. If Layer 2 is the service stack, this is the wiring that turns five Claude Code projects into a coordinated team.

## Services

| Doc | Service | Port / Endpoint |
|-----|---------|----------------|
| [scoped-mcp.md](scoped-mcp.md) | Per-agent MCP proxy — manifest-controlled tool surface | stdio |
| [steward.md](steward.md) | Sole proposer of changes to the root-owned agent-config surface | systemd, own port |
| [forge-config-mcp.md](forge-config-mcp.md) | Closed op vocabulary steward uses to author config proposals | systemd, own port |
| [agent-bus.md](agent-bus.md) | Inter-agent event log, HMAC signing, NATS federation | 8495 |
| [task-queue-mcp.md](task-queue-mcp.md) | Task queue MCP server | 8496 |
| [task-queue-widget.md](task-queue-widget.md) | Task queue dashboard widget (React, embedded in Matrix) | 3004 |
| [task-dispatcher.md](task-dispatcher.md) | Task routing and headless agent session launcher | — (PM2) |
| [pool-manager.md](pool-manager.md) | Ephemeral agent session directory pre-warming | — (PM2) |
| [synapse.md](synapse.md) | Matrix homeserver (Synapse) | 8008 |
| [matrix-mcp.md](matrix-mcp.md) | Matrix send/receive MCP server | 8487 |
| [matrix-dispatcher.md](matrix-dispatcher.md) | Matrix → agent task dispatch loop | — (PM2) |
| [matrix-admin-bot.md](matrix-admin-bot.md) | Matrix room administration bot | — (PM2) |
| [matrix-hitl-bot.md](matrix-hitl-bot.md) | Matrix front end for scoped-mcp HITL approve/deny | — (PM2, outbound only) |
| [matrix-task-queue-bot.md](matrix-task-queue-bot.md) | Matrix task queue notification bot | — (PM2) |
| [nats.md](nats.md) | NATS JetStream event bus | 4222 |
| [nats-mcp.md](nats-mcp.md) | NATS publish/subscribe MCP server | 8497 |
| [dragonfly.md](dragonfly.md) | Agent state backend (Redis-compatible) | 6379 |
| [webhook-doorman.md](webhook-doorman.md) | Fail-closed inbound webhook router (GitHub, Vikunja, Grafana) | 8507 |

## How It Fits Together

```
Operator → Matrix room → matrix-dispatcher → agent project dir
                                                    ↓
                                     scoped-mcp reads manifest
                                                    ↓
                              agent ↔ MCP proxy ↔ backend services
                                                    ↓
                                    agent-bus logs event → NATS
```

Cross-agent work flows through the task queue: research hands off build plans to developer, developer hands off doc updates to writer.
