# Diagnostics Check

diag-check is a PM2 cron job that runs the agent panel's lightweight diagnostics every 6 hours and sends alerts via push notification when checks fail. It's the automated monitoring layer on top of the [agent panel's](agent-panel.md) diagnostics system — the panel provides the checks, diag-check runs them on a schedule.

It sits in [Layer 2](../../README.md#layer-2--self-hosted-service-stack) of the architecture as part of the health monitoring surface.

## How It Works

The script is minimal — a curl wrapper around the agent panel's diagnostics API:

1. Reads the panel auth token from the panel's `.env` file
2. POSTs to the panel's `/api/diagnostics/run-lightweight` endpoint
3. Parses the JSON response for pass/warn/fail counts
4. Logs a summary line with timestamp
5. Exits with code 1 if any checks fail

The agent panel's lightweight diagnostics check:

- **Docker containers** — expected containers are running
- **PM2 processes** — expected services are online
- **NFS mounts** — storage mounts are accessible
- **Listening ports** — expected ports are responding
- **TLS certificate expiry** — certs aren't about to expire
- **Git repo state** — tracked repos aren't dirty
- **DNS resolution** — external DNS works
- **Cross-host ping** — storage network hosts are reachable
- **Endpoint health** — key services respond to HTTP checks

The full check list is configured in the agent panel's `config/config.js`. Adding a new Docker container or PM2 service to the expected list means editing the panel config, not this script.

## Runtime

- **PM2 service:** `diag-check`
- **Schedule:** Every 6 hours (`0 */6 * * *`)
- **Script:** `~/scripts/run-diagnostics.sh`
- **Depends on:** Agent panel running on port 3003

## Failure Handling

When checks fail:
- The script exits with code 1 (PM2 marks the run as errored)
- Check the panel's diagnostics UI or PM2 logs for details: `pm2 logs diag-check --lines 20`

When the panel itself is down:
- The curl request fails, the script exits with an error
- This shows up as a diag-check failure in PM2, which is itself a signal that something is wrong

## Relationship to Agent Panel

diag-check doesn't implement any checks — it delegates entirely to the agent panel. Think of it as a cron trigger for the panel's diagnostics:

- **Agent panel** — defines checks, runs them on demand or via API, displays results in the web UI
- **diag-check** — calls the panel API on a schedule, alerts on failures

If you want to add or modify checks, edit the agent panel's config. If you want to change the check frequency or alerting, edit the PM2 cron schedule or the script.

## Related Docs

- [Agent Panel](agent-panel.md) — diagnostics system, check configuration, web UI
- [PM2 ecosystem config](../../pm2/ecosystem.config.js.example) — cron schedule
