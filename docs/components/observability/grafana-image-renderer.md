# Grafana Image Renderer

Grafana Image Renderer is a headless Chromium service that renders Grafana panels and
dashboards to PNG for sharing, alerting attachments, and scheduled reports. On forge it
uses AMD iGPU hardware acceleration via DRI passthrough.

- **Image:** `grafana/grafana-image-renderer:latest` (SHA-pinned in compose)
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Network:** `forge-monitoring` only (no external access)

## AMD iGPU DRI Passthrough

The MS-A2 has an AMD integrated GPU. The renderer uses it via the DRI render node:

```yaml
devices:
  - /dev/dri/renderD128:/dev/dri/renderD128
group_add:
  - "992"   # render group GID on forge
```

`renderD128` is the AMD iGPU render node. GID `992` is the `render` group on forge.
The renderer uses this for hardware-accelerated headless Chromium rendering.

## Rendering Configuration

```yaml
environment:
  - ENABLE_METRICS=true
  - RENDERING_MODE=clustered
  - RENDERING_CLUSTERING_MODE=browser
  - RENDERING_CLUSTERING_MAX_CONCURRENCY=4
```

`RENDERING_MODE=clustered` allows multiple concurrent render requests. With
`RENDERING_CLUSTERING_MAX_CONCURRENCY=4`, up to 4 panels can render simultaneously.
`RENDERING_CLUSTERING_MODE=browser` reuses Chromium instances across renders rather
than spawning a new browser per request.

## Grafana Integration

Grafana connects to the renderer via two env vars in the Grafana container:

```yaml
environment:
  - GF_RENDERING_SERVER_URL=http://renderer:8081/render
  - GF_RENDERING_CALLBACK_URL=http://grafana:3000/
  - GF_LOG_FILTERS=rendering:debug
```

`GF_RENDERING_SERVER_URL` points to the renderer on `forge-monitoring`. The callback
URL must be the internal Grafana address (not the SWAG subdomain) since the renderer
calls back to Grafana on the internal network.

## No External Access

The renderer has no published ports and is not on `forge-net`. It is only reachable by
Grafana on `forge-monitoring`. External rendering requests go through Grafana's API,
not directly to the renderer.

## Related Docs

- [forge-observability-stack.md](../../phases/forge-observability-stack.md) — build narrative
