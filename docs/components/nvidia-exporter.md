# nvidia-smi Exporter

Prometheus metrics exporter for the forge RTX 2000 Ada GPU. Exposes hardware telemetry — temperature, memory, power draw, and utilization — scraped via `nvidia-smi`.

## Stack

| Setting | Value |
|---------|-------|
| Image | `utkuozdemir/nvidia_gpu_exporter:1.3.0` (pinned) |
| Container | `nvidia-exporter` |
| Port | `127.0.0.1:9835` (localhost-only — no forge-net membership) |
| Runtime | `nvidia` |
| Compose | `~/docker/nvidia-exporter/docker-compose.yml` |

The container mounts `nvidia-smi` and `libnvidia-ml.so.1` from the host read-only — it doesn't need a full GPU driver stack inside the image.

## Metrics

All metrics carry a `uuid` label identifying the GPU device.

| Metric | Description |
|--------|-------------|
| `nvidia_smi_temperature_gpu` | GPU temperature (°C) |
| `nvidia_smi_memory_used_bytes` | VRAM in use |
| `nvidia_smi_memory_total_bytes` | Total VRAM |
| `nvidia_smi_power_draw_watts` | Current power draw |
| `nvidia_smi_utilization_gpu_ratio` | GPU compute utilization (0–1) |
| `nvidia_smi_utilization_memory_ratio` | Memory controller utilization (0–1) |

Metrics endpoint: `http://localhost:9835/metrics`

## Scraping

The exporter is not on `forge-net` — it runs on the default Docker bridge only. A Prometheus scraper inside a container cannot reach it by container name. Scrape via the host:

```yaml
# Prometheus scrape config (from a host-network scraper or via host IP)
- job_name: nvidia_gpu
  static_configs:
    - targets: ['localhost:9835']
```

**Grafana integration:** Deferred. The Telegraf/Prometheus scrape path for this host is TBD. No external exposure; metrics are host-local until a scraper is wired up.

## Notes

- No authentication — localhost-only, no external access
- Not backed up (stateless exporter, rebuildable)
- L4 from security audit: accepted that nvidia-exporter is not on forge-net — scraping from host localhost is sufficient for the intended use case

## Related Docs

- [ollama.md](ollama.md) — GPU inference stack (same build)
