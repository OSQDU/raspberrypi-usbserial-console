#!/bin/bash
# modules/udev/uninstall.sh - Udev module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling udev module..."

    # Remove udev rules
    rm -f /etc/udev/rules.d/99-usb-serial-console.rules

    # Remove console scripts
    rm -f /usr/local/bin/console
    rm -f /usr/local/bin/list-consoles

    # Reload udev rules
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules
        udevadm trigger
    fi

    log_success "Udev module uninstalled successfully"
}

main "$@"