#!/bin/bash
# modules/services/uninstall.sh - Services coordination module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling services coordination module..."

    # Stop all coordinated services
    local services=(dnsmasq nginx tftpd-hpa smbd nmbd)
    
    for service in "${services[@]}"; do
        systemctl stop "${service}" 2>/dev/null || true
    done

    # Remove service coordination scripts if they exist
    rm -f /usr/local/bin/usbserial-start-services
    rm -f /usr/local/bin/usbserial-stop-services
    rm -f /etc/systemd/system/usbserial-services.service

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    log_success "Services coordination module uninstalled successfully"
}

main "$@"