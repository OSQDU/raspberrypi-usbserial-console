#!/bin/bash
# modules/network/install.sh - Network configuration setup

source "../../lib/common.sh"

main() {
    log_info "Installing network module..."
    
    # Configure IP forwarding
    configure_ip_forwarding
    
    # Configure NetworkManager
    configure_network_manager
    
    log_success "Network module installed successfully"
}

configure_ip_forwarding() {
    log_info "Configuring IP forwarding..."
    
    # Deploy sysctl configuration
    backup_file "/etc/sysctl.d/10-router.conf"
    replace_file "10-router.conf" "/etc/sysctl.d/10-router.conf"
    
    # Apply immediately
    sysctl -p /etc/sysctl.d/10-router.conf
    
    log_info "IP forwarding enabled for IPv4 and IPv6"
}

configure_network_manager() {
    log_info "Configuring NetworkManager for hostapd compatibility..."
    
    # Create NetworkManager configuration to ignore wlan0 when acting as AP
    cat > /etc/NetworkManager/conf.d/99-unmanage-wlan0.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    
    # Reload NetworkManager configuration
    systemctl reload NetworkManager 2>/dev/null || true
    
    log_info "NetworkManager configured to ignore wlan0 interface"
}

main "$@"