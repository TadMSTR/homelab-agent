# Telegraf

Telegraf collects host-level system metrics and Docker container metrics on forge, shipping them to InfluxDB v3. It runs inside the observability stack on the `forge-monitoring` network with no host port exposure.

- **Image:** `telegraf:latest` (v1.38.4)
- **Compose:** `~/docker/observability/docker-compose.yml`
- **Appdata:** `/opt/appdata/observability/telegraf/`
- **Network:** `forge-monitoring` (internal only)
- **Port:** None exposed — collection-only agent

## Configuration

Config file: `/opt/appdata/observability/telegraf/telegraf.conf` (mounted read-only).

**Agent settings:**
- `interval = 30s`, `flush_interval = 30s`
- `hostname = "forge"`
- `metric_batch_size = 5000`, `metric_buffer_limit = 50000`
- `collection_jitter = 5s`, `flush_jitter = 5s`

**Input plugins:**

| Plugin | What it collects |
|--------|-----------------|
| `inputs.cpu` | CPU usage (total only, not per-core) |
| `inputs.mem` | Memory usage |
| `inputs.disk` | Disk usage (ignores tmpfs, devtmpfs, overlay) |
| `inputs.diskio` | Disk I/O |
| `inputs.net` | Network interface stats |
| `inputs.system` | Uptime, load averages |
| `inputs.swap` | Swap usage |
| `inputs.processes` | Process counts by state |
| `inputs.docker` | Container metrics via Docker socket |

**Output:**

| Plugin | Destination | Auth |
|--------|------------|------|
| `outputs.influxdb_v3` | `http://influxdb:8181` | Token via `$INFLUXDB_TOKEN` env var, database `forge` |

## Host Access

Telegraf needs read-only access to host filesystems and the Docker socket for collection:

| Mount | Container path | Purpose |
|-------|---------------|---------|
| `/var/run/docker.sock` | `/var/run/docker.sock` (ro) | Docker container metrics |
| `/proc` | `/proc` (ro) | System metrics |
| `/sys` | `/sys` (ro) | System metrics |
| `/` | `/rootfs` (ro) | Disk usage |

Docker socket access is granted via `group_add: 989` (Docker socket GID).

## Credentials

Telegraf loads `~/.secrets/forge.env` via `env_file`. It uses `INFLUXDB_TOKEN` from that file. Note: the full secrets file is loaded, so all variables in `forge.env` are available inside the container.

## Dependencies

- **InfluxDB** — output destination (must be running, Telegraf has `depends_on: influxdb`)
- **Docker socket** — required for container metrics collection

## Operations

**Restart:**
```bash
docker compose -f ~/docker/observability/docker-compose.yml restart telegraf
```

**View logs:**
```bash
docker logs telegraf --tail 50
```

**Test config:**
```bash
docker exec telegraf telegraf --test --config /etc/telegraf/telegraf.conf
```
