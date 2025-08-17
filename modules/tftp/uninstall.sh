#!/bin/bash
# modules/tftp/uninstall.sh - TFTP module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling TFTP module..."

    # Stop and disable service
    systemctl stop tftpd-hpa 2>/dev/null || true
    systemctl disable tftpd-hpa 2>/dev/null || true

    # Backup and remove configuration
    if [[ -f "/etc/default/tftpd-hpa" ]]; then
        backup_file "/etc/default/tftpd-hpa"
        rm -f "/etc/default/tftpd-hpa"
    fi

    # Remove tftp from upload group
    if getent group upload >/dev/null 2>&1; then
        gpasswd -d tftp upload 2>/dev/null || true
    fi

    # Note: We don't remove the tftpd-hpa package as it might be used by other services

    log_success "TFTP module uninstalled successfully"
}

main "$@"