#!/bin/bash
# modules/dnsmasq/uninstall.sh - DNSmasq module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling dnsmasq module..."

    # Stop and disable service
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl disable dnsmasq 2>/dev/null || true

    # Backup and remove configuration
    if [[ -f "/etc/dnsmasq.conf" ]]; then
        backup_file "/etc/dnsmasq.conf"
        rm -f "/etc/dnsmasq.conf"
    fi

    # Remove dynamic IPv6 configs if they exist
    rm -f /etc/dnsmasq.d/ipv6-dynamic.conf

    # Note: We don't remove the dnsmasq package as it might be used by other services

    log_success "Dnsmasq module uninstalled successfully"
}

main "$@"