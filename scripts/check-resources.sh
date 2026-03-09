#!/bin/bash
# Resource Monitor — checks system health and alerts on thresholds
# Triggered by PM2 cron (see pm2/ecosystem.config.js.example)

LOG="$HOME/.local/share/logs/resource-usage-$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$LOG")"

# Replace with your notification endpoint
NTFY_URL=""  # e.g., "https://ntfy.example.com/your-topic"
ALERTS=""

# RAM usage
MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
MEM_USED=$(free -m | awk '/Mem:/{print $3}')
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
echo "RAM: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)" >> "$LOG"
if [ "$MEM_PCT" -gt 85 ]; then
    ALERTS="${ALERTS}RAM at ${MEM_PCT}% (${MEM_USED}MB/${MEM_TOTAL}MB)\n"
fi

# Disk usage (root partition — add more partitions as needed)
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
echo "Disk: ${DISK_USED} / ${DISK_TOTAL} (${DISK_PCT}%)" >> "$LOG"
if [ "$DISK_PCT" -gt 80 ]; then
    ALERTS="${ALERTS}Disk at ${DISK_PCT}% (${DISK_USED}/${DISK_TOTAL})\n"
fi

# Docker container health
if command -v docker &>/dev/null; then
    DOCKER_RUNNING=$(docker ps -q 2>/dev/null | wc -l)
    DOCKER_TOTAL=$(docker ps -aq 2>/dev/null | wc -l)
    echo "Docker: ${DOCKER_RUNNING}/${DOCKER_TOTAL} containers running" >> "$LOG"
    DOCKER_UNHEALTHY=$(docker ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null)
    if [ -n "$DOCKER_UNHEALTHY" ]; then
        ALERTS="${ALERTS}Unhealthy containers: ${DOCKER_UNHEALTHY}\n"
    fi
fi

# PM2 process status
if command -v pm2 &>/dev/null; then
    PM2_ERRORED=$(pm2 jlist 2>/dev/null | python3 -c "
import sys,json
procs = json.load(sys.stdin)
errored = [p['name'] for p in procs if p.get('pm2_env',{}).get('status') == 'errored']
print(','.join(errored) if errored else '')
" 2>/dev/null)
    PM2_COUNT=$(pm2 jlist 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
    echo "PM2: ${PM2_COUNT} processes" >> "$LOG"
    if [ -n "$PM2_ERRORED" ]; then
        ALERTS="${ALERTS}PM2 errored: ${PM2_ERRORED}\n"
    fi
fi

# NFS mount check — add your mount points here
# if ! mountpoint -q /mnt/your-nfs-mount 2>/dev/null; then
#     ALERTS="${ALERTS}NFS mount /mnt/your-nfs-mount is DOWN\n"
# fi

# Report
if [ -n "$ALERTS" ]; then
    echo -e "ALERTS:\n$ALERTS" >> "$LOG"
    if [ -n "$NTFY_URL" ]; then
        curl -s -H "Title: Resource alert" -H "Priority: high" -H "Tags: warning" \
            -d "$(echo -e "$ALERTS")" "$NTFY_URL" > /dev/null
    fi
fi

# Cleanup old logs
find "$(dirname "$LOG")" -name "resource-usage-*.log" -mtime +30 -delete
