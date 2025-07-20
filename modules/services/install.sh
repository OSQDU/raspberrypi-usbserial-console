#!/bin/bash
# modules/services/install.sh - Systemd service coordination

set -euo pipefail

# Source common functions with validation
if [[ ! -f "../../lib/common.sh" ]]; then
    echo "ERROR: Cannot find common.sh library" >&2
    exit 1
fi

source "../../lib/common.sh"

# Module-specific error handling
services_error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "Services module installation failed: $msg"
    cleanup_on_error
    exit "$code"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial services installation..."
    
    # Stop and disable service
    systemctl stop usbserial-console 2>/dev/null || true
    systemctl disable usbserial-console 2>/dev/null || true
    
    # Remove installed files
    rm -f /etc/systemd/system/usbserial-console.service
    rm -f /usr/local/bin/usbserial-startup
    rm -f /usr/local/bin/usbserial-shutdown
    
    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true
    
    log_info "Services cleanup completed"
}

main() {
    log_info "Installing service coordination module..."
    
    # Create systemd service for coordination
    create_coordination_service || services_error_exit "Failed to create coordination service"
    
    # Create service startup script
    create_startup_script || services_error_exit "Failed to create startup scripts"
    
    log_success "Service coordination module installed successfully"
}

create_coordination_service() {
    log_info "Creating systemd service coordination..."
    
    # Create systemd system directory if it doesn't exist
    if ! mkdir -p /etc/systemd/system; then
        log_error "Failed to create systemd system directory"
        return 1
    fi
    
    # Create main coordination service
    if ! cat > /etc/systemd/system/usbserial-console.service << 'EOF'
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
    then
        log_error "Failed to create usbserial-console.service"
        return 1
    fi
    
    # Set proper permissions
    if ! chmod 644 /etc/systemd/system/usbserial-console.service; then
        log_error "Failed to set permissions on service file"
        return 1
    fi
    
    # Reload systemd configuration
    if ! systemctl daemon-reload; then
        log_error "Failed to reload systemd configuration"
        return 1
    fi
    
    # Enable the service
    if ! manage_service enable usbserial-console; then
        log_error "Failed to enable usbserial-console service"
        return 1
    fi
    
    log_info "Coordination service created successfully"
}

create_startup_script() {
    log_info "Creating service startup script..."
    
    # Create /usr/local/bin directory if it doesn't exist
    if ! mkdir -p /usr/local/bin; then
        log_error "Failed to create /usr/local/bin directory"
        return 1
    fi
    
    # Create startup script
    if ! cat > /usr/local/bin/usbserial-startup << 'EOF'
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
    then
        log_error "Failed to create startup script"
        return 1
    fi
    
    # Create shutdown script
    if ! cat > /usr/local/bin/usbserial-shutdown << 'EOF'
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
    then
        log_error "Failed to create shutdown script"
        return 1
    fi
    
    # Make scripts executable
    if ! chmod +x /usr/local/bin/usbserial-startup; then
        log_error "Failed to make startup script executable"
        return 1
    fi
    
    if ! chmod +x /usr/local/bin/usbserial-shutdown; then
        log_error "Failed to make shutdown script executable"
        return 1
    fi
    
    # Validate scripts were created correctly
    if [[ ! -x "/usr/local/bin/usbserial-startup" ]]; then
        log_error "Startup script not executable after creation"
        return 1
    fi
    
    if [[ ! -x "/usr/local/bin/usbserial-shutdown" ]]; then
        log_error "Shutdown script not executable after creation"
        return 1
    fi
    
    log_info "Service scripts created successfully"
}

main "$@"
