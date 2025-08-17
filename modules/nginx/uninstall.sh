#!/bin/bash
# modules/nginx/uninstall.sh - Nginx module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling nginx module..."

    # Stop and disable service
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true

    # Remove site configurations
    rm -f /etc/nginx/sites-available/usbserial
    rm -f /etc/nginx/sites-enabled/usbserial

    # Restore default site if backup exists
    if [[ -f "/etc/nginx/sites-available/default.backup" ]]; then
        mv "/etc/nginx/sites-available/default.backup" "/etc/nginx/sites-available/default"
        ln -sf "/etc/nginx/sites-available/default" "/etc/nginx/sites-enabled/default"
    fi

    # Remove upload interface
    rm -f /srv/shared/upload.html

    # Remove temporary upload directories
    rm -rf /tmp/nginx_uploads

    # Remove www-data from upload group
    if getent group upload >/dev/null 2>&1; then
        gpasswd -d www-data upload 2>/dev/null || true
    fi

    # Note: We don't remove the nginx package as it might be used by other services

    log_success "Nginx module uninstalled successfully"
}

main "$@"