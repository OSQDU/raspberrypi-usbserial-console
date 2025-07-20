#!/bin/bash
# modules/dnsmasq/install.sh - DNS and DHCP server setup

source "../../lib/common.sh"

main() {
    log_info "Installing dnsmasq module..."
    
    # Deploy configuration
    deploy_dnsmasq_config
    
    # Configure dnsmasq service
    configure_dnsmasq_service
    
    log_success "Dnsmasq module installed successfully"
}

deploy_dnsmasq_config() {
    log_info "Deploying dnsmasq configuration..."
    
    local wifi_interface ethernet_interface
    wifi_interface=$(get_wifi_interface)
    ethernet_interface=$(get_ethernet_interface)
    
    # Process template if it exists, otherwise use static config
    if [[ -f "dnsmasq.conf.template" ]]; then
        process_template \
            "dnsmasq.conf.template" \
            "/etc/dnsmasq.conf" \
            "WIFI_INTERFACE" "$wifi_interface" \
            "ETHERNET_INTERFACE" "$ethernet_interface"
    else
        # Backup and deploy static config
        backup_file "/etc/dnsmasq.conf"
        replace_file "dnsmasq.conf" "/etc/dnsmasq.conf"
    fi
    
    # Set proper permissions
    chmod 644 /etc/dnsmasq.conf
    
    # Create DHCP lease directory
    mkdir -p /var/lib/dhcp
    chown dnsmasq:nogroup /var/lib/dhcp 2>/dev/null || true
}

configure_dnsmasq_service() {
    log_info "Configuring dnsmasq service..."
    
    # Enable but don't start yet (will be handled by service coordination)
    manage_service enable dnsmasq
}

main "$@"