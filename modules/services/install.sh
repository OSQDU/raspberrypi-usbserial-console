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
    rm -f "${SCRIPT_DIR}/usbserial-startup"
    
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
    
        "SERVICE_START_TIMEOUT" "${SERVICE_START_TIMEOUT}"; then
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
    
    # Create script directory if it doesn't exist
    if ! mkdir -p "${SCRIPT_DIR}"; then
        log_error "Failed to create script directory: ${SCRIPT_DIR}"
        return 1
    fi
    
        "WIFI_IPV4_GATEWAY" "${WIFI_IPV4_GATEWAY}"; then
        log_error "Failed to create startup script"
        return 1
    fi
    
    if ! chmod +x "${SCRIPT_DIR}/usbserial-startup"; then
        log_error "Failed to make startup script executable"
        return 1
    fi
    
    # Validate script was created correctly
    if [[ ! -x "${SCRIPT_DIR}/usbserial-startup" ]]; then
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
