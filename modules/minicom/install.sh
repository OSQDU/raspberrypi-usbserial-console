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
    
    # Create console access scripts
    cat > /usr/local/bin/console << 'EOF'
#!/bin/bash
# Quick serial console access script

DEVICE="${1:-/dev/usbserial-1}"

if [[ ! -e "$DEVICE" ]]; then
    echo "Error: Serial device $DEVICE not found"
    echo "Available devices:"
    ls /dev/usbserial-* 2>/dev/null || echo "  No USB serial devices found"
    exit 1
fi

echo "Connecting to $DEVICE..."
echo "Press Ctrl+A X to exit minicom"
exec minicom -D "$DEVICE"
EOF
    
    chmod +x /usr/local/bin/console
    
    # Create device listing script
    cat > /usr/local/bin/list-consoles << 'EOF'
#!/bin/bash
# List available serial console devices

echo "USB Serial Console Devices:"
echo "=========================="

if ls /dev/usbserial-* >/dev/null 2>&1; then
    for device in /dev/usbserial-*; do
        device_name=$(basename "$device")
        if [[ -c "$device" ]]; then
            echo "  $device_name -> $device"
        fi
    done
else
    echo "  No USB serial devices found"
    echo ""
    echo "Make sure USB serial adapters are connected and udev rules are loaded."
fi

echo ""
echo "Usage: console [device]"
echo "Example: console /dev/usbserial-1.0"
EOF
    
    chmod +x /usr/local/bin/list-consoles
    
    log_info "Created console access scripts:"
    log_info "  console [device]     - Connect to serial device"
    log_info "  list-consoles        - List available devices"
}

main "$@"