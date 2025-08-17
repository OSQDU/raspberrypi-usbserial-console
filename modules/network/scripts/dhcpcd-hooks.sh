#!/bin/bash
# /etc/dhcpcd.exit-hooks.d/usb-serial-console
# DHCPv6-PD hook for USB Serial Console

set -euo pipefail

readonly CONFIG_SCRIPT="/usr/local/bin/configure-nat"
readonly LOCKFILE="/var/run/usbserial-dhcp-hook.lock"
readonly MAX_BACKGROUND_JOBS=3

# Logging function
log_hook() {
    local level="$1"
    local message="$2"
    logger -t "usb-serial-dhcp" -p "daemon.${level}" "${message}"
}

# Check if configuration script exists and is executable
validate_config_script() {
    if [[ ! -x "${CONFIG_SCRIPT}" ]]; then
        log_hook "err" "Configuration script not found or not executable: ${CONFIG_SCRIPT}"
        return 1
    fi
    return 0
}

# Prevent multiple concurrent executions
acquire_lock() {
    local timeout=30
    local count=0

    while [[ ${count} -lt ${timeout} ]]; do
        if (set -C; echo $$ > "${LOCKFILE}") 2>/dev/null; then
            # Set trap to cleanup lock on exit
            trap 'rm -f "${LOCKFILE}"' EXIT
            return 0
        fi

        # Check if existing lock is stale
        if [[ -f "${LOCKFILE}" ]]; then
            local lock_pid
            lock_pid=$(cat "${LOCKFILE}" 2>/dev/null || echo "")
            if [[ -n "${lock_pid}" ]] && ! kill -0 "${lock_pid}" 2>/dev/null; then
                log_hook "warning" "Removing stale lock file (PID ${lock_pid})"
                rm -f "${LOCKFILE}"
                continue
            fi
        fi

        sleep 1
        ((count++))
    done

    log_hook "err" "Failed to acquire lock after ${timeout}s"
    return 1
}

# Limit number of background jobs
limit_background_jobs() {
    local job_count
    job_count=$(pgrep -f "configure-nat dhcpv6-hook" | wc -l)

    if [[ ${job_count} -ge ${MAX_BACKGROUND_JOBS} ]]; then
        log_hook "warning" "Too many background jobs (${job_count}), skipping this event"
        return 1
    fi
    return 0
}

# Execute configuration with proper error handling
execute_config() {
    local reason="$1"
    local delay="${2:-0}"

    # Validate environment
    validate_config_script || return 1

    # Acquire lock to prevent concurrent execution
    if ! acquire_lock; then
        return 1
    fi

    # Limit background jobs
    if ! limit_background_jobs; then
        return 1
    fi

    # Add delay if requested
    if [[ ${delay} -gt 0 ]]; then
        sleep "${delay}"
    fi

    # Execute configuration script
    log_hook "info" "Executing NAT reconfiguration due to ${reason}"
    if "${CONFIG_SCRIPT}" dhcpv6-hook; then
        log_hook "info" "NAT reconfiguration completed successfully"
    else
        log_hook "err" "NAT reconfiguration failed"
        return 1
    fi
}

# Main hook logic
main() {
    # Validate required variables
    if [[ -z "${interface:-}" ]]; then
        log_hook "err" "Interface variable not set"
        return 1
    fi

    if [[ -z "${reason:-}" ]]; then
        log_hook "err" "Reason variable not set"
        return 1
    fi

    # Only handle eth0 events
    if [[ "${interface}" != "eth0" ]]; then
        return 0
    fi

    case "${reason}" in
        BOUND6|REBIND6|REBOOT6|RENEW6)
            # DHCPv6-PD event on eth0, reconfigure everything
            log_hook "info" "DHCPv6 event on eth0 (${reason})"
            execute_config "${reason}" 0 &
            ;;
        EXPIRE6|RELEASE6|STOP6)
            # IPv6 lost on eth0, reconfigure with fallback
            log_hook "info" "IPv6 expired on eth0 (${reason})"
            execute_config "${reason}" 0 &
            ;;
        BOUND|REBIND|REBOOT|RENEW)
            # IPv4 event on eth0, brief delay then check IPv6 changes
            log_hook "info" "IPv4 event on eth0 (${reason})"
            execute_config "${reason}" 2 &
            ;;
        *)
            # Unknown reason, log but don't act
            log_hook "debug" "Ignoring event on eth0 (${reason})"
            ;;
    esac
}

# Execute main function with error handling
if ! main; then
    log_hook "err" "Hook execution failed for interface=${interface} reason=${reason}"
    exit 1
fi
