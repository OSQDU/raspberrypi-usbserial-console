#!/bin/bash
# modules/udev/install.sh - USB serial device rules

source "../../lib/common.sh"

main() {
    log_info "Installing udev rules module..."

    # Deploy udev rules
    deploy_udev_rules

    # Reload udev rules
    reload_udev_rules

    log_success "Udev module installed successfully"
}

deploy_udev_rules() {
    log_info "Deploying USB serial device rules..."

    # Copy rules file
    cp "10-ch341-usbserial.rules" "/etc/udev/rules.d/"

    # Set proper permissions
    chmod 644 "/etc/udev/rules.d/10-ch341-usbserial.rules"
}

reload_udev_rules() {
    log_info "Reloading udev rules..."

    udevadm control --reload-rules
    udevadm trigger --subsystem-match=tty
}

main "$@"
