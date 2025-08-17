#!/bin/bash
# lib/common.sh - Common utilities and functions for USB Serial Console setup

# Prevent multiple sourcing
[[ -n "${COMMON_SH_LOADED:-}" ]] && return 0
readonly COMMON_SH_LOADED=1

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Project configuration
readonly PROJECT_NAME="USB Serial Console"
readonly PROJECT_VERSION="2.0"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2
}

log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] && echo -e "[DEBUG] $(date '+%H:%M:%S') $*" >&2
    return 0
}

# Load global configuration
load_global_config() {
    local config_file
    local script_dir

    # Find the script directory relative to where this function is called
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

    # Look for config file in several locations
    local config_paths=(
        "${script_dir}/../config/global.conf"
        "${script_dir}/../../config/global.conf"
        "${script_dir}/../../../config/global.conf"
        "/etc/usbserial/global.conf"
        "/usr/local/share/usbserial/global.conf"
    )

    for config_file in "${config_paths[@]}"; do
        if [[ -f "$config_file" && -r "$config_file" ]]; then
            # shellcheck source=/dev/null
            source "$config_file"
            log_debug "Loaded configuration from: $config_file"
            return 0
        fi
    done

    log_warn "Global configuration file not found, using defaults"
    return 1
}

# Auto-load configuration when this library is sourced
load_global_config

# Error handling
error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# Check if running as root
require_root() {
    [[ $EUID -eq 0 ]] || error_exit "This operation requires root privileges. Please run with sudo."
}

# Check if running as non-root
require_user() {
    [[ $EUID -ne 0 ]] || error_exit "This operation should not be run as root."
}

# File operations with backup
backup_file() {
    local file="$1"
    local backup_dir="${2:-$CONFIG_DIR/backups}"

    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S)
        local backup_file
        backup_file="$backup_dir/$(basename "$file").bak.$timestamp"
        cp "$file" "$backup_file"
        log_info "Backed up $file to $backup_file"
    fi
}

# Safe file replacement
replace_file() {
    local source="$1"
    local target="$2"
    local backup="${3:-true}"

    [[ -f "$source" ]] || error_exit "Source file does not exist: $source"

    if [[ "$backup" == "true" ]]; then
        backup_file "$target"
    fi

    cp "$source" "$target"
    log_info "Replaced $target with $source"
}

# Template processing
process_template() {
    local template="$1"
    local output="$2"
    shift 2

    [[ -f "$template" ]] || error_exit "Template file does not exist: $template"

    local content
    content=$(cat "$template")

    # Replace variables in format {{VARIABLE}}
    while [[ $# -gt 0 ]]; do
        local var="$1"
        local value="$2"
        content=${content//\{\{$var\}\}/$value}
        shift 2
    done

    echo "$content" > "$output"
    log_info "Generated $output from template $template"
}

# Service management
manage_service() {
    local action="$1"
    local service="$2"

    case "$action" in
        enable)
            systemctl enable "$service"
            log_info "Enabled service: $service"
            ;;
        disable)
            systemctl disable "$service" 2>/dev/null || true
            log_info "Disabled service: $service"
            ;;
        start)
            systemctl start "$service"
            log_info "Started service: $service"
            ;;
        stop)
            systemctl stop "$service" 2>/dev/null || true
            log_info "Stopped service: $service"
            ;;
        restart)
            systemctl restart "$service"
            log_info "Restarted service: $service"
            ;;
        reload)
            systemctl reload "$service" 2>/dev/null || systemctl restart "$service"
            log_info "Reloaded service: $service"
            ;;
        status)
            if systemctl is-active --quiet "$service"; then
                log_success "$service is running"
            else
                log_warn "$service is not running"
            fi
            ;;
        *)
            error_exit "Unknown service action: $action"
            ;;
    esac
}

# Package management
install_package() {
    local package="$1"

    if ! dpkg -l "$package" >/dev/null 2>&1; then
        log_info "Installing package: $package"
        apt-get update -qq
        apt-get install -y "$package"
        log_success "Installed package: $package"
    else
        log_info "Package already installed: $package"
    fi
}

remove_package() {
    local package="$1"

    if dpkg -l "$package" >/dev/null 2>&1; then
        log_info "Removing package: $package"
        apt-get remove -y "$package"
        log_success "Removed package: $package"
    else
        log_info "Package not installed: $package"
    fi
}

# Network utilities
get_wifi_interface() {
    local interface
    interface=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')
    echo "${interface:-wlan0}"
}

get_ethernet_interface() {
    local interface
    interface=$(ip route | awk '/default/ && /eth/ {print $5; exit}')
    echo "${interface:-eth0}"
}

get_mac_address() {
    local interface="$1"
    local mac_addr

    if [[ -f "/sys/class/net/$interface/address" ]]; then
        mac_addr=$(cat "/sys/class/net/$interface/address")
    else
        mac_addr=$(ip link show "$interface" 2>/dev/null | awk '/link\/ether/ {print $2}')
    fi

    echo "$mac_addr"
}

# Hardware detection
detect_pi_model() {
    local model
    if [[ -f "/proc/device-tree/model" ]]; then
        model=$(tr -d '\0' < /proc/device-tree/model)
    else
        model="Unknown Raspberry Pi"
    fi
    echo "$model"
}

detect_pi_version() {
    local model
    model=$(detect_pi_model)

    case "$model" in
        *"Pi 5"*) echo "5" ;;
        *"Pi 4"*) echo "4" ;;
        *"Pi 3"*) echo "3" ;;
        *"Pi Zero 2"*) echo "zero2" ;;
        *"Pi Zero"*) echo "zero" ;;
        *) echo "unknown" ;;
    esac
}

# Validation functions
validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ $ip =~ $regex ]]; then
        local IFS='.'
        local -a octets
        read -ra octets <<< "${ip//./ }"
        [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]
    else
        return 1
    fi
}

validate_mac() {
    local mac="$1"
    local regex='^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'
    [[ $mac =~ $regex ]]
}

# Progress indication
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"

    local percentage=$((current * 100 / total))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))

    printf "\r${BLUE}[%s%s]${NC} %d%% %s" \
        "$(printf "%*s" $filled | tr ' ' '█')" \
        "$(printf "%*s" $empty | tr ' ' '░')" \
        "$percentage" \
        "$description"

    [[ $current -eq $total ]] && echo
}

# Configuration helpers
create_config_dirs() {
    local dirs=("$CONFIG_DIR" "$LOG_DIR" "$SHARED_DIR")

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log_debug "Created directory: $dir"
    done
}

# Export functions for use in other scripts
export -f log_info log_success log_warn log_error log_debug error_exit
export -f require_root require_user backup_file replace_file process_template
export -f manage_service install_package remove_package
export -f get_wifi_interface get_ethernet_interface get_mac_address
export -f detect_pi_model detect_pi_version validate_ip validate_mac
export -f show_progress create_config_dirs
