#!/bin/bash
# modules/hostapd/install.sh - WiFi Access Point setup

source "../../lib/common.sh"

main() {
    log_info "Installing hostapd module..."
    
    # Package is already installed by module system
    # Deploy configuration
    deploy_hostapd_config
    
    # Generate WPA PSK
    generate_wpa_psk
    
    # Configure hostapd service
    configure_hostapd_service
    
    log_success "Hostapd module installed successfully"
}

deploy_hostapd_config() {
    log_info "Deploying hostapd configuration..."
    
    local wifi_interface
    wifi_interface=$(get_wifi_interface)
    
    # Process template
    process_template \
        "hostapd.conf.template" \
        "/etc/hostapd/hostapd.conf" \
        "WIFI_INTERFACE" "$wifi_interface" \
        "COUNTRY_CODE" "US"
    
    # Backup and deploy
    backup_file "/etc/hostapd/hostapd.conf"
    replace_file "hostapd.conf" "/etc/hostapd/hostapd.conf"
    
    # Set proper permissions
    chmod 644 /etc/hostapd/hostapd.conf
}

generate_wpa_psk() {
    log_info "Generating WPA PSK..."
    
    local wifi_interface
    wifi_interface=$(get_wifi_interface)
    
    local mac_addr
    mac_addr=$(get_mac_address "$wifi_interface")
    
    if [[ -z "$mac_addr" ]]; then
        error_exit "Could not determine MAC address for $wifi_interface"
    fi
    
    # Clean MAC address (remove colons, convert to uppercase)
    local clean_mac
    clean_mac=$(echo "$mac_addr" | tr -d ':' | tr 'a-f' 'A-F')
    
    # Create PSK file
    echo "00:00:00:00:00:00 $clean_mac" > /etc/hostapd/hostapd.wpa_psk
    chmod 600 /etc/hostapd/hostapd.wpa_psk
    
    log_info "WiFi credentials:"
    log_info "  SSID: USBSerial-Console"
    log_info "  Password: $clean_mac"
}

configure_hostapd_service() {
    log_info "Configuring hostapd service..."
    
    # Point hostapd to our config file
    sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
    
    # Enable but don't start yet (will be handled by service coordination)
    manage_service enable hostapd
}

main "$@"