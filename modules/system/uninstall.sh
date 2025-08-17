#!/bin/bash
# modules/system/uninstall.sh - System module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling system module..."

    # Remove logrotate configuration
    if [[ -f "/etc/logrotate.d/usbserial" ]]; then
        backup_file "/etc/logrotate.d/usbserial"
        rm -f "/etc/logrotate.d/usbserial"
        log_info "Removed logrotate configuration"
    fi

    # Note: We don't remove essential packages as they might be used by other services
    # Note: We don't revert hostname/timezone changes as they're permanent system changes

    log_success "System module uninstalled successfully"
}

main "$@"