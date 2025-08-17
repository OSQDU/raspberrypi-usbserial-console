#!/bin/bash
# modules/minicom/uninstall.sh - Minicom module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling minicom module..."

    # Remove minicom configuration files
    rm -f /etc/minicom/minirc.dfl
    rm -f /etc/minicom/minirc.usbserial*

    # Remove console access scripts if they were created by minicom module
    # (Note: These might be created by udev module instead)
    if [[ -f "/usr/local/bin/console" ]]; then
        # Check if this was created by minicom module
        if grep -q "minicom" "/usr/local/bin/console" 2>/dev/null; then
            rm -f /usr/local/bin/console
        fi
    fi

    # Note: We don't remove the minicom package as it might be used by other services

    log_success "Minicom module uninstalled successfully"
}

main "$@"