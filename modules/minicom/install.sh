#!/bin/bash
# modules/minicom/install.sh - Serial console configuration

source "../../lib/common.sh"

main() {
    log_info "Installing minicom module..."
    
    # Deploy configuration
    deploy_minicom_config
    
    # Configure user permissions
    configure_serial_permissions
    
    log_success "Minicom module installed successfully"
}

deploy_minicom_config() {
    log_info "Deploying minicom configuration..."
    
    # Create minicom config directory
    mkdir -p /etc/minicom
    
    # Deploy default configuration
    backup_file "/etc/minicom/minirc.dfl"
    replace_file "minirc.dfl" "/etc/minicom/minirc.dfl"
    
    # Set proper permissions
    chmod 644 /etc/minicom/minirc.dfl
    
    # Update config to use new device naming
    sed -i 's|/dev/ttyUSB0|/dev/usbserial-1|g' /etc/minicom/minirc.dfl
}

configure_serial_permissions() {
    log_info "Configuring serial device permissions..."
    
    # Add pi user to dialout group for serial access
    usermod -a -G dialout pi
    
    # Create convenience scripts
    create_serial_scripts
}

create_serial_scripts() {
    log_info "Creating serial console scripts..."
    
    # Create console access script from template
    if ! process_template \
        "templates/console.sh" \
        "${SCRIPT_DIR}/console" \
        "USB_DEVICE_PREFIX" "${USB_DEVICE_PREFIX}"; then
        log_error "Failed to create console script"
        return 1
    fi
    
    chmod +x "${SCRIPT_DIR}/console"
    
    # Create device listing script from template
    if ! process_template \
        "templates/list-consoles.sh" \
        "${SCRIPT_DIR}/list-consoles" \
        "USB_DEVICE_PREFIX" "${USB_DEVICE_PREFIX}"; then
        log_error "Failed to create list-consoles script"
        return 1
    fi
    
    chmod +x "${SCRIPT_DIR}/list-consoles"
    
    log_info "Created console access scripts:"
    log_info "  console [device]     - Connect to serial device"
    log_info "  list-consoles        - List available devices"
}

main "$@"
