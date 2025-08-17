#!/bin/bash
# modules/network/uninstall.sh - Network module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling network module..."

    # Stop and disable services
    systemctl stop setup-nat 2>/dev/null || true
    systemctl disable setup-nat 2>/dev/null || true
    systemctl stop update-issue.timer 2>/dev/null || true
    systemctl disable update-issue.timer 2>/dev/null || true

    # Remove NetworkManager hotspot connection
    nmcli connection delete "USBSerial-Console" 2>/dev/null || true
    rm -f /etc/NetworkManager/system-connections/USBSerial-Console.nmconnection

    # Remove installed files
    rm -f /etc/systemd/system/setup-nat.service
    rm -f /etc/systemd/system/update-issue.service
    rm -f /etc/systemd/system/update-issue.timer
    rm -f /usr/local/bin/configure-nat
    rm -f /usr/local/bin/update-issue
    rm -rf /usr/local/share/usbserial/templates
    rm -f /etc/dhcpcd.exit-hooks.d/usb-serial-console
    rm -f /etc/NetworkManager/conf.d/99-disable-dnsmasq.conf
    # Restore original IP.issue content
    cat > /etc/issue.d/IP.issue << 'EOF'
IPv4: \4{eth0} \4{wlan0}
IPv6: \6{eth0} \6{wlan0}

EOF
    log_info "Restored original IP.issue content"
    
    rm -f /var/lib/usbserial/ip-state

    # Remove sysctl configuration (backup first)
    if [[ -f "/etc/sysctl.d/10-router.conf" ]]; then
        backup_file "/etc/sysctl.d/10-router.conf"
        rm -f "/etc/sysctl.d/10-router.conf"
    fi

    # Remove nftables configuration (backup first)
    if [[ -f "/etc/nftables.conf" ]]; then
        backup_file "/etc/nftables.conf"
        nft flush ruleset 2>/dev/null || true
    fi

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    log_success "Network module uninstalled successfully"
}

main "$@"