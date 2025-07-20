#!/bin/bash
# modules/services/install.sh - Systemd service coordination

source "../../lib/common.sh"

main() {
    log_info "Installing service coordination module..."
    
    # Create systemd service for coordination
    create_coordination_service
    
    # Create service startup script
    create_startup_script
    
    log_success "Service coordination module installed successfully"
}

create_coordination_service() {
    log_info "Creating systemd service coordination..."
    
    # Create main coordination service
    cat > /etc/systemd/system/usbserial-console.service << 'EOF'
[Unit]
Description=USB Serial Console Access Point
After=multi-user.target network.target
Wants=hostapd.service dnsmasq.service nginx.service tftpd-hpa.service smbd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usbserial-startup
ExecStop=/usr/local/bin/usbserial-shutdown
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service
    systemctl daemon-reload
    manage_service enable usbserial-console
}

create_startup_script() {
    log_info "Creating service startup script..."
    
    # Create startup script
    cat > /usr/local/bin/usbserial-startup << 'EOF'
#!/bin/bash
# USB Serial Console startup script

set -euo pipefail

LOG_FILE="/var/log/usbserial/startup.log"
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
    local timeout=30
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
    wait_for_interface "wlan0"
    
    # Start services in order
    local services=("hostapd" "dnsmasq" "nginx" "tftpd-hpa" "smbd" "nmbd")
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
        log "  WiFi: USBSerial-Console"
        log "  Web:  http://192.168.44.1/"
        log "  TFTP: tftp://192.168.44.1/"
        log "  SMB:  \\\\192.168.44.1\\shared"
        
        return 0
    else
        log "Failed to start services: ${failed_services[*]}"
        return 1
    fi
}

main "$@"
EOF
    
    # Create shutdown script
    cat > /usr/local/bin/usbserial-shutdown << 'EOF'
#!/bin/bash
# USB Serial Console shutdown script

set -euo pipefail

LOG_FILE="/var/log/usbserial/shutdown.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

stop_service() {
    local service="$1"
    log "Stopping service: $service"
    
    if systemctl stop "$service" 2>/dev/null; then
        log "Service stopped: $service"
    else
        log "Service stop failed or not running: $service"
    fi
}

main() {
    log "Stopping USB Serial Console services..."
    
    # Stop services in reverse order
    local services=("nmbd" "smbd" "tftpd-hpa" "nginx" "dnsmasq" "hostapd")
    
    for service in "${services[@]}"; do
        stop_service "$service"
    done
    
    log "USB Serial Console services stopped"
}

main "$@"
EOF
    
    # Make scripts executable
    chmod +x /usr/local/bin/usbserial-startup
    chmod +x /usr/local/bin/usbserial-shutdown
}

main "$@"