#!/bin/bash

#######################################
# Docker Compose Stack Backup Script
#
# Backs up Docker Compose stacks by:
#   1. Running pre-flight checks (Docker, disk space, paths)
#   2. Discovering stacks with appdata bind mounts
#   3. Stopping each stack, archiving compose + appdata, restarting
#   4. Sending notifications on success/failure
#
# Supports: gzip, bzip2, xz, zstd, parallel compression, dry-run mode
# Notifications: ntfy, Pushover, email (configure below)
#
# Usage:
#   sudo ./docker-stack-backup.sh           # Run backup
#   sudo ./docker-stack-backup.sh --dry-run # Simulate without changes
#
# Forked from: https://github.com/TadMSTR/docker-stack-backup
#######################################

set -euo pipefail

#######################################
# OS Detection
#######################################
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"

        case "$OS_ID" in
            debian)  OS_TYPE="debian" ;;
            ubuntu)  OS_TYPE="ubuntu" ;;
            *)
                if [[ -f /etc/debian_version ]]; then
                    OS_TYPE="debian"
                else
                    OS_TYPE="unknown"
                fi
                ;;
        esac
    else
        OS_TYPE="unknown"
        OS_NAME="Unknown"
    fi

    export OS_TYPE OS_NAME OS_ID OS_VERSION
}

detect_os

# Dry-run mode flag
DRY_RUN=false

# ── Configuration ─────────────────────────────────────────────────────────────
# Customize these paths for your environment:
STACK_BASE="$HOME/docker"                # Directory containing stack subdirs (each with a compose file)
APPDATA_PATH="/opt/appdata"              # Bind mount root for all stack appdata
BACKUP_DEST="/mnt/backup/docker-backups" # Where backups are stored (local path or NFS mount)
LOG_FILE="/var/log/docker-stack-backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)

# Compression
COMPRESSION_METHOD="none"   # Options: gzip, bzip2, xz, zstd, none
COMPRESSION_LEVEL=6
USE_PARALLEL=false
PARALLEL_THREADS=0

# Exclude patterns (relative to appdata directory)
EXCLUDE_PATTERNS=(
    # "*/cache/*"
    # "*/tmp/*"
    # "*.log"
)

# Notifications
NOTIFY_ON_SUCCESS=true
NOTIFY_ON_FAILURE=true

# Ntfy — replace with your ntfy server and topic
NTFY_ENABLED=false
NTFY_URL=""       # e.g., "https://ntfy.example.com"
NTFY_TOPIC=""     # e.g., "my-server"
NTFY_PRIORITY="default"
NTFY_TOKEN=""

# Pushover (disabled by default)
PUSHOVER_ENABLED=false
PUSHOVER_USER_KEY=""
PUSHOVER_API_TOKEN=""
PUSHOVER_PRIORITY=0

# Email (disabled by default)
EMAIL_ENABLED=false
EMAIL_TO=""
EMAIL_FROM="docker-backup@$(hostname)"
EMAIL_SUBJECT_PREFIX="[Docker Backup]"
EMAIL_METHOD="sendmail"
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT="587"
SMTP_USER=""
SMTP_PASSWORD=""
SMTP_USE_TLS=true
SMTP_INSECURE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

#######################################
# Logging
#######################################
log()         { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"; }

#######################################
# File locking
#######################################
LOCK_FILE="/var/run/docker-stack-backup.lock"
LOCK_FD=200

acquire_lock() {
    eval "exec $LOCK_FD>$LOCK_FILE"
    if ! flock -n $LOCK_FD; then
        log_error "Another backup is already running (lock file: $LOCK_FILE)"
        log_error "If you're sure no backup is running, remove: $LOCK_FILE"
        exit 1
    fi
    echo $$ >&$LOCK_FD
    log "Lock acquired (PID: $$)"
}

release_lock() {
    if [[ -n "${LOCK_FD:-}" ]]; then
        flock -u $LOCK_FD 2>/dev/null || true
        rm -f "$LOCK_FILE" 2>/dev/null || true
        log "Lock released"
    fi
}

trap release_lock EXIT INT TERM

#######################################
# Pre-flight checks
#######################################
check_docker_running() {
    if ! systemctl is-active --quiet docker 2>/dev/null && ! pgrep -x dockerd >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon not responding"
        return 1
    fi
    log "✓ Docker daemon is running"
    return 0
}

check_disk_space() {
    local path="$1"
    local min_free_gb="${2:-5}"
    mkdir -p "$path" 2>/dev/null || true
    if [[ ! -d "$path" ]]; then
        log_error "Backup destination does not exist: $path"
        return 1
    fi
    local available_kb=$(df -k "$path" | awk 'NR==2 {print $4}')
    local available_gb=$((available_kb / 1024 / 1024))
    if [[ $available_gb -lt $min_free_gb ]]; then
        log_error "Insufficient disk space on $path (${available_gb}GB available, ${min_free_gb}GB required)"
        return 1
    fi
    log "✓ Disk space: ${available_gb}GB available on $path"
    return 0
}

check_mount_point() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        log_warning "Path does not exist: $path (will be created)"
        return 0
    fi
    if ! touch "$path/.write-test" 2>/dev/null; then
        log_error "Cannot write to $path — check permissions and mount status"
        return 1
    fi
    rm -f "$path/.write-test"
    if mountpoint -q "$path" 2>/dev/null; then
        log "✓ $path is a mount point ($(df -h "$path" | awk 'NR==2 {print $1}')"
    else
        log "✓ $path is accessible (local filesystem)"
    fi
    return 0
}

check_required_paths() {
    log "Checking required paths..."
    if [[ ! -d "$STACK_BASE" ]]; then
        log_error "Stack base directory not found: $STACK_BASE"
        return 1
    fi
    log "✓ Stack base exists: $STACK_BASE"
    if [[ ! -d "$APPDATA_PATH" ]]; then
        log_error "Appdata directory not found: $APPDATA_PATH"
        return 1
    fi
    log "✓ Appdata directory exists: $APPDATA_PATH"
    return 0
}

run_preflight_checks() {
    log "========================================="
    log "Running pre-flight checks..."
    log "========================================="
    local checks_passed=true
    check_docker_running  || checks_passed=false
    check_required_paths  || checks_passed=false
    check_mount_point "$BACKUP_DEST" || checks_passed=false
    check_disk_space "$BACKUP_DEST" 5 || checks_passed=false
    if [[ "$checks_passed" == false ]]; then
        log_error "Pre-flight checks failed!"
        return 1
    fi
    log "========================================="
    log "✓ All pre-flight checks passed"
    log "========================================="
    return 0
}

#######################################
# Restart with retry
#######################################
MAX_RESTART_ATTEMPTS=3
RESTART_RETRY_DELAY=5

restart_stack_with_retry() {
    local stack_path="$1"
    local stack_name=$(basename "$stack_path")
    local running_containers="$2"
    local attempt=1

    while [[ $attempt -le $MAX_RESTART_ATTEMPTS ]]; do
        log "Starting containers (attempt $attempt/$MAX_RESTART_ATTEMPTS)..."
        if (cd "$stack_path" && docker compose up -d $running_containers 2>&1 | tee -a "$LOG_FILE"); then
            sleep 2
            local started_count=$(cd "$stack_path" && docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
            local expected_count=$(echo "$running_containers" | wc -w)
            if [[ $started_count -eq $expected_count ]]; then
                log_success "All containers started successfully"
                return 0
            else
                log_warning "Only $started_count of $expected_count containers started"
            fi
        fi
        if [[ $attempt -lt $MAX_RESTART_ATTEMPTS ]]; then
            log_warning "Restart failed, waiting ${RESTART_RETRY_DELAY}s before retry..."
            sleep $RESTART_RETRY_DELAY
        fi
        ((attempt++))
    done

    log_error "Failed to restart stack after $MAX_RESTART_ATTEMPTS attempts: $stack_name"
    log_error "Manual restart: cd $stack_path && docker compose up -d $running_containers"
    send_critical_restart_failure "$stack_name" "$stack_path" "$running_containers"
    return 1
}

send_critical_restart_failure() {
    local stack_name="$1"
    local stack_path="$2"
    local containers="$3"
    local title="CRITICAL: Stack Failed to Restart - $HOSTNAME"
    local message="Stack '$stack_name' failed to restart after backup!

⚠️  IMMEDIATE ACTION REQUIRED ⚠️

Stack: $stack_name
Host: $HOSTNAME
Containers: $containers

Manual restart:
cd $stack_path && docker compose up -d $containers

Logs: $LOG_FILE"

    [[ "$NTFY_ENABLED" == true ]]     && send_ntfy "$title" "$message" "urgent" "warning,backup"
    [[ "$PUSHOVER_ENABLED" == true ]] && send_pushover "$title" "$message" 1
    [[ "$EMAIL_ENABLED" == true ]]    && send_email "[CRITICAL] $title" "$message"
}

#######################################
# Notifications
#######################################
send_ntfy() {
    [[ "$NTFY_ENABLED" != true ]] && return 0
    local title="$1" message="$2" priority="${3:-$NTFY_PRIORITY}" tags="${4:-backup}"
    local curl_args=(-X POST -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" -d "$message")
    [[ -n "$NTFY_TOKEN" ]] && curl_args+=(-H "Authorization: Bearer $NTFY_TOKEN")
    curl -s "${curl_args[@]}" "$NTFY_URL/$NTFY_TOPIC" >/dev/null 2>&1 || log_error "Failed to send Ntfy notification"
}

send_pushover() {
    [[ "$PUSHOVER_ENABLED" != true ]] && return 0
    [[ -z "$PUSHOVER_USER_KEY" || -z "$PUSHOVER_API_TOKEN" ]] && { log_error "Pushover enabled but credentials not configured"; return 1; }
    local title="$1" message="$2" priority="${3:-$PUSHOVER_PRIORITY}"
    curl -s \
        --form-string "token=$PUSHOVER_API_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "title=$title" \
        --form-string "message=$message" \
        --form-string "priority=$priority" \
        https://api.pushover.net/1/messages.json >/dev/null 2>&1 || log_error "Failed to send Pushover notification"
}

send_email_sendmail() {
    local subject="$1" body="$2"
    command -v sendmail &>/dev/null || { log_error "sendmail not found"; return 1; }
    (echo "To: $EMAIL_TO"; echo "From: $EMAIL_FROM"; echo "Subject: $subject"; echo ""; echo "$body") | sendmail -t
}

send_email_smtp() {
    local subject="$1" body="$2"
    local smtp_url="smtp://$SMTP_SERVER:$SMTP_PORT"
    [[ "$SMTP_USE_TLS" == true ]] && smtp_url="smtps://$SMTP_SERVER:$SMTP_PORT"
    local email_content="From: $EMAIL_FROM
To: $EMAIL_TO
Subject: $subject

$body"
    local curl_args=(--url "$smtp_url" --mail-from "$EMAIL_FROM" --mail-rcpt "$EMAIL_TO" --upload-file -)
    [[ -n "$SMTP_USER" && -n "$SMTP_PASSWORD" ]] && curl_args+=(--user "$SMTP_USER:$SMTP_PASSWORD")
    [[ "${SMTP_INSECURE:-false}" == true ]] && curl_args+=(--insecure)
    echo "$email_content" | curl -s "${curl_args[@]}" >/dev/null 2>&1 || { log_error "Failed to send email via SMTP"; return 1; }
}

send_email() {
    [[ "$EMAIL_ENABLED" != true ]] && return 0
    [[ -z "$EMAIL_TO" ]] && { log_error "Email enabled but EMAIL_TO not configured"; return 1; }
    case "$EMAIL_METHOD" in
        sendmail) send_email_sendmail "$1" "$2" ;;
        smtp)     send_email_smtp "$1" "$2" ;;
        *)        log_error "Unknown email method: $EMAIL_METHOD"; return 1 ;;
    esac
}

send_notifications() {
    local status="$1" backed_up="$2" skipped="$3" failed="$4" total="$5"
    [[ "$status" == "success" && "$NOTIFY_ON_SUCCESS" != true ]] && return 0
    [[ "$status" == "failure" && "$NOTIFY_ON_FAILURE" != true ]] && return 0

    local title message priority tags
    if [[ "$status" == "success" ]]; then
        title="Docker Backup Complete - $HOSTNAME"
        priority="default"; tags="white_check_mark,backup"
        message="Backup completed successfully

✓ Successfully backed up: $backed_up
⊘ Skipped (no appdata): $skipped
✗ Failed: $failed
━━━━━━━━━━━━━━━━━━━━
Total stacks: $total
Time: $(date +'%Y-%m-%d %H:%M:%S')"
    else
        title="Docker Backup FAILED - $HOSTNAME"
        priority="high"; tags="x,backup,warning"
        message="Backup completed with errors

✓ Successfully backed up: $backed_up
⊘ Skipped (no appdata): $skipped
✗ FAILED: $failed
━━━━━━━━━━━━━━━━━━━━
Total stacks: $total
Time: $(date +'%Y-%m-%d %H:%M:%S')

Logs: $LOG_FILE"
    fi

    send_ntfy "$title" "$message" "$priority" "$tags"
    send_pushover "$title" "$message" "$([ "$status" == "failure" ] && echo 1 || echo 0)"
    send_email "$EMAIL_SUBJECT_PREFIX $title" "$message"
}

#######################################
# Compression
#######################################
get_compression_extension() {
    case "$COMPRESSION_METHOD" in
        gzip)  echo ".tar.gz"  ;;
        bzip2) echo ".tar.bz2" ;;
        xz)    echo ".tar.xz"  ;;
        zstd)  echo ".tar.zst" ;;
        none)  echo ".tar"     ;;
        *)     echo ".tar.gz"  ;;
    esac
}

get_tar_compression_flag() {
    [[ "$USE_PARALLEL" == true ]] && { echo ""; return; }
    case "$COMPRESSION_METHOD" in
        gzip)  echo "z"      ;;
        bzip2) echo "j"      ;;
        xz)    echo "J"      ;;
        zstd)  echo "--zstd" ;;
        none)  echo ""       ;;
        *)     echo "z"      ;;
    esac
}

setup_compression_environment() {
    case "$COMPRESSION_METHOD" in
        gzip)  export GZIP="-${COMPRESSION_LEVEL}"  ;;
        bzip2) export BZIP2="-${COMPRESSION_LEVEL}" ;;
        xz)    export XZ_OPT="-${COMPRESSION_LEVEL}" ;;
    esac
}

check_compression_tool() {
    command -v "$1" &>/dev/null || { log_warning "$1 not found"; return 1; }
}

create_compressed_archive() {
    local output_file="$1"; shift
    local tar_args=("$@")
    setup_compression_environment
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do exclude_args+=(--exclude="$pattern"); done

    if [[ "$USE_PARALLEL" == true ]]; then
        local compressor="" compressor_args=()
        case "$COMPRESSION_METHOD" in
            gzip)
                check_compression_tool pigz && compressor="pigz" compressor_args=("-${COMPRESSION_LEVEL}") || USE_PARALLEL=false
                [[ $PARALLEL_THREADS -gt 0 && -n "$compressor" ]] && compressor_args+=("-p" "$PARALLEL_THREADS") ;;
            bzip2)
                check_compression_tool pbzip2 && compressor="pbzip2" compressor_args=("-${COMPRESSION_LEVEL}") || USE_PARALLEL=false
                [[ $PARALLEL_THREADS -gt 0 && -n "$compressor" ]] && compressor_args+=("-p${PARALLEL_THREADS}") ;;
            xz)
                check_compression_tool pxz && compressor="pxz" compressor_args=("-${COMPRESSION_LEVEL}") || USE_PARALLEL=false
                [[ $PARALLEL_THREADS -gt 0 && -n "$compressor" ]] && compressor_args+=("-T${PARALLEL_THREADS}") ;;
            zstd)
                check_compression_tool zstd || return 1
                compressor="zstd" compressor_args=("-${COMPRESSION_LEVEL}")
                [[ $PARALLEL_THREADS -gt 0 ]] && compressor_args+=("-T${PARALLEL_THREADS}") ;;
            none)
                tar -cf "$output_file" "${exclude_args[@]}" "${tar_args[@]}"; return $? ;;
        esac
        [[ "$USE_PARALLEL" == true && -n "$compressor" ]] && {
            tar -c "${exclude_args[@]}" "${tar_args[@]}" | "$compressor" "${compressor_args[@]}" > "$output_file"
            return $?
        }
    fi

    local compression_flag=$(get_tar_compression_flag)
    if [[ "$compression_flag" == "--zstd" ]]; then
        check_compression_tool zstd || { log_error "zstd not found"; return 1; }
        tar -c $compression_flag -f "$output_file" "${exclude_args[@]}" "${tar_args[@]}"
    elif [[ -n "$compression_flag" ]]; then
        tar -c${compression_flag}f "$output_file" "${exclude_args[@]}" "${tar_args[@]}"
    else
        tar -cf "$output_file" "${exclude_args[@]}" "${tar_args[@]}"
    fi
}

#######################################
# Stack discovery
#######################################
find_compose_file() {
    local stack_path="$1"
    for name in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        [[ -f "$stack_path/$name" ]] && { echo "$stack_path/$name"; return 0; }
    done
    return 1
}

stack_has_appdata() {
    local compose_file="$1"
    [[ -f "$compose_file" ]] && grep -q "$APPDATA_PATH" "$compose_file"
}

#######################################
# Dry-run simulation
#######################################
simulate_backup_stack() {
    local stack_path="$1"
    local stack_name=$(basename "$stack_path")
    local compose_file
    compose_file=$(find_compose_file "$stack_path") || return 2
    stack_has_appdata "$compose_file" || return 2
    local appdata_dir="$APPDATA_PATH/$stack_name"
    [[ -d "$appdata_dir" ]] || return 2

    local size=$(du -sh "$appdata_dir" 2>/dev/null | cut -f1)
    local size_bytes=$(du -sb "$appdata_dir" 2>/dev/null | cut -f1)
    local running_count=0
    (cd "$stack_path" && docker compose ps --services --filter "status=running" 2>/dev/null | grep -q .) && \
        running_count=$(cd "$stack_path" && docker compose ps --services --filter "status=running" 2>/dev/null | wc -l) || true

    if [[ $running_count -gt 0 ]]; then
        echo "  ${GREEN}✓${NC} $stack_name ($size appdata, $running_count running)"
    else
        echo "  ${YELLOW}○${NC} $stack_name ($size appdata, stopped)"
    fi
    echo "$size_bytes" > /tmp/stack_size_$$
    return 0
}

#######################################
# Backup a single stack
#######################################
backup_stack() {
    local stack_path="$1"
    local stack_name=$(basename "$stack_path")

    local compose_file
    compose_file=$(find_compose_file "$stack_path") || { log_warning "No compose file in $stack_name"; return 0; }

    log "Processing stack: $stack_name"

    if ! stack_has_appdata "$compose_file"; then
        log_warning "Stack $stack_name has no appdata bind mounts, skipping"
        return 2
    fi

    local appdata_dir="$APPDATA_PATH/$stack_name"
    if [[ ! -d "$appdata_dir" ]]; then
        log_warning "Appdata directory not found: $appdata_dir — skipping"
        return 2
    fi
    if [[ -z "$(ls -A "$appdata_dir" 2>/dev/null)" ]]; then
        log_warning "Appdata directory is empty: $appdata_dir"
        return 0
    fi

    local backup_dir="$BACKUP_DEST/$HOSTNAME/$TIMESTAMP"
    mkdir -p "$backup_dir"
    local backup_ext=$(get_compression_extension)
    local backup_file="$backup_dir/${stack_name}${backup_ext}"

    log "Checking container states for stack: $stack_name"
    local running_containers
    running_containers=$(cd "$stack_path" && docker compose ps --services --filter "status=running" 2>/dev/null || true)

    if [[ -z "$running_containers" ]]; then
        log_warning "No running containers in $stack_name, skipping"
        return 0
    fi
    log "Running containers: $(echo "$running_containers" | tr '\n' ',' | sed 's/,$//')"

    log "Stopping stack: $stack_name"
    (cd "$stack_path" && docker compose down) || { log_error "Failed to stop stack $stack_name"; return 1; }

    local temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN
    cp "$compose_file" "$temp_dir/"
    [[ -f "$stack_path/.env" ]] && cp "$stack_path/.env" "$temp_dir/"

    log "Creating ${COMPRESSION_METHOD} backup: $backup_file"
    if create_compressed_archive "$backup_file" \
        -C "$temp_dir" . \
        -C "$APPDATA_PATH" "$stack_name" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Backup created: $backup_file"
    else
        log_error "Backup failed for $stack_name — attempting restart"
        [[ -n "$running_containers" ]] && (cd "$stack_path" && docker compose up -d $running_containers)
        return 1
    fi

    log "Restarting previously running containers: $(echo "$running_containers" | tr '\n' ',' | sed 's/,$//')"
    restart_stack_with_retry "$stack_path" "$running_containers" || return 1

    log_success "Stack $stack_name backed up and restarted successfully"
    return 0
}

#######################################
# Main
#######################################
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|--dryrun|-n) DRY_RUN=true; shift ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run, -n    Simulate backup without making changes"
                echo "  --help, -h       Show this help message"
                exit 0 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BOLD}${CYAN}=========================================${NC}"
        echo -e "${BOLD}${CYAN}DRY RUN MODE - No changes will be made${NC}"
        echo -e "${BOLD}${CYAN}=========================================${NC}\n"
    fi

    log "========================================="
    [[ "$DRY_RUN" == true ]] && log "DRY RUN: Docker stack backup simulation" || log "Starting Docker stack backup"
    log "Host: $HOSTNAME"
    log "OS: $OS_NAME ($OS_TYPE)"
    log "Stack base: $STACK_BASE"
    log "Appdata: $APPDATA_PATH"
    log "Backup dest: $BACKUP_DEST"
    log "========================================="

    [[ $EUID -ne 0 ]] && { log_error "This script must be run as root"; exit 1; }
    [[ "$DRY_RUN" != true ]] && acquire_lock

    run_preflight_checks || { log_error "Pre-flight checks failed, aborting"; exit 1; }

    local total_stacks=0 backed_up=0 skipped=0 failed=0 total_size=0

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}Stacks that would be backed up:${NC}\n"
        local -a skip_list

        for stack_path in "$STACK_BASE"/*/; do
            [[ -d "$stack_path" ]] || continue
            find_compose_file "$stack_path" >/dev/null 2>&1 || continue
            total_stacks=$((total_stacks + 1))

            if simulate_backup_stack "$stack_path"; then
                backed_up=$((backed_up + 1))
                if [[ -f /tmp/stack_size_$$ ]]; then
                    total_size=$((total_size + $(cat /tmp/stack_size_$$)))
                    rm -f /tmp/stack_size_$$
                fi
            else
                local compose_file
                compose_file=$(find_compose_file "$stack_path" 2>/dev/null) && skip_list+=("$(basename "$stack_path")")
                skipped=$((skipped + 1))
            fi
        done

        if [[ ${#skip_list[@]} -gt 0 ]]; then
            echo -e "\n${YELLOW}Would skip (no appdata):${NC}"
            for s in "${skip_list[@]}"; do echo "  ${YELLOW}○${NC} $s"; done
        fi

        local total_size_human=$(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "${total_size} bytes")
        echo -e "\n${CYAN}=========================================${NC}"
        echo "  Total stacks: $total_stacks"
        echo -e "  Would backup: ${GREEN}$backed_up${NC}"
        echo -e "  Would skip:   ${YELLOW}$skipped${NC}"
        echo "  Estimated size: ${BOLD}$total_size_human${NC} (uncompressed)"
        echo "  Compression: ${COMPRESSION_METHOD}"

        local available_kb=$(df -k "$BACKUP_DEST" 2>/dev/null | awk 'NR==2 {print $4}')
        local available_bytes=$((available_kb * 1024))
        local available_human=$(numfmt --to=iec-i --suffix=B $available_bytes 2>/dev/null || echo "unknown")
        echo "  Space available: $available_human"
        [[ $available_bytes -gt $total_size ]] \
            && echo -e "  ${GREEN}✓ Sufficient space available${NC}" \
            || echo -e "  ${RED}✗ Insufficient space!${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${BOLD}${GREEN}DRY RUN COMPLETE - No actions taken${NC}\n"
        log "Dry run complete — would backup: $backed_up stacks"
        return 0
    fi

    # Normal backup
    for stack_path in "$STACK_BASE"/*/; do
        [[ -d "$stack_path" ]] || continue
        find_compose_file "$stack_path" >/dev/null 2>&1 || continue
        total_stacks=$((total_stacks + 1))

        local result=0
        backup_stack "$stack_path" || result=$?
        case $result in
            0) backed_up=$((backed_up + 1)) ;;
            2) skipped=$((skipped + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
    done

    log "========================================="
    log "Backup Summary:"
    log "  Total stacks: $total_stacks"
    log "  Backed up:    $backed_up"
    log "  Skipped:      $skipped"
    log "  Failed:       $failed"
    log "========================================="

    if [[ $failed -gt 0 ]]; then
        send_notifications "failure" "$backed_up" "$skipped" "$failed" "$total_stacks"
        exit 1
    else
        send_notifications "success" "$backed_up" "$skipped" "$failed" "$total_stacks"
    fi
}

main "$@"
