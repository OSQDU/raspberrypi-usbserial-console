#!/bin/bash
# USB Serial Console startup script

set -euo pipefail

LOG_FILE="{{LOG_DIR}}/startup.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

start_service() {
    local service="$1"
    log "Starting service: $service"

    if systemctl start "$service"; then
        log "Service started successfully: $service"
        return 0
    else
        log "Failed to start service: $service"
        return 1
    fi
}

wait_for_interface() {
    local interface="$1"
    local timeout={{INTERFACE_WAIT_TIMEOUT}}
    local count=0

    log "Waiting for interface: $interface"

    while [[ $count -lt $timeout ]]; do
        if ip link show "$interface" >/dev/null 2>&1; then
            log "Interface ready: $interface"
            return 0
        fi
        sleep 1
        ((count++))
    done

    log "Timeout waiting for interface: $interface"
    return 1
}

main() {
    log "Starting USB Serial Console services..."

    # Wait for WiFi interface
    wait_for_interface "{{WIFI_INTERFACE}}"

    # Start services in order
    local services=({{SERVICES_LIST}})
    local failed_services=()

    for service in "${services[@]}"; do
        if ! start_service "$service"; then
            failed_services+=("$service")
        fi
        sleep 2  # Brief pause between service starts
    done

    if [[ ${#failed_services[@]} -eq 0 ]]; then
        log "All services started successfully"

        # Show access information
        log "USB Serial Console is ready:"
        log "  WiFi: {{WIFI_SSID}}"
        log "  Web:  http://{{WIFI_IPV4_GATEWAY}}/"
        log "  TFTP: tftp://{{WIFI_IPV4_GATEWAY}}/"
        log "  SMB:  \\\\{{WIFI_IPV4_GATEWAY}}\\shared"

        return 0
    else
        log "Failed to start services: ${failed_services[*]}"
        return 1
    fi
}

main "$@"
