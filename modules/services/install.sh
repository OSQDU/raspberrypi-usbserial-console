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
    log_error "Services module installation failed: ${msg}"
    cleanup_on_error
    exit "${code}"
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

# Validate module files exist
validate_module_files() {
    local required_files=(
        "templates/usbserial-console.service"
        "templates/usbserial-startup.sh"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            services_error_exit "Required module file not found: ${file}"
        fi

        if [[ ! -r "${file}" ]]; then
            services_error_exit "Required module file not readable: ${file}"
        fi
    done

    log_debug "All module files validated"
}

main() {
    log_info "Installing service coordination module..."

    # Validate module files exist
    validate_module_files

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

    # Process and deploy systemd service template
    if ! process_template \
        "templates/usbserial-console.service" \
        "/etc/systemd/system/usbserial-console.service" \
        "SCRIPT_DIR" "${SCRIPT_DIR}" \
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

    # Process and deploy startup script template
    if ! process_template \
        "templates/usbserial-startup.sh" \
        "${SCRIPT_DIR}/usbserial-startup" \
        "LOG_DIR" "${LOG_DIR}" \
        "INTERFACE_WAIT_TIMEOUT" "${INTERFACE_WAIT_TIMEOUT}" \
        "WIFI_INTERFACE" "${WIFI_INTERFACE}" \
        "SERVICES_LIST" "${SERVICES_LIST}" \
        "WIFI_SSID" "${WIFI_SSID}" \
        "WIFI_IPV4_GATEWAY" "${WIFI_IPV4_GATEWAY}"; then
        log_error "Failed to create startup script"
        return 1
    fi

    # Make script executable
    if ! chmod +x "${SCRIPT_DIR}/usbserial-startup"; then
        log_error "Failed to make startup script executable"
        return 1
    fi

    # Validate script was created correctly
    if [[ ! -x "${SCRIPT_DIR}/usbserial-startup" ]]; then
        log_error "Startup script not executable after creation"
        return 1
    fi

    log_info "Service startup script created successfully"
}

main "$@"
