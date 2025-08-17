#!/bin/bash
# modules/samba/uninstall.sh - Samba module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling Samba module..."

    # Stop and disable services
    systemctl stop smbd 2>/dev/null || true
    systemctl stop nmbd 2>/dev/null || true
    systemctl disable smbd 2>/dev/null || true
    systemctl disable nmbd 2>/dev/null || true

    # Backup and remove configuration
    if [[ -f "/etc/samba/smb.conf" ]]; then
        backup_file "/etc/samba/smb.conf"
        rm -f "/etc/samba/smb.conf"
    fi

    # Remove samba users (backup user database first)
    if [[ -f "/var/lib/samba/private/passdb.tdb" ]]; then
        backup_file "/var/lib/samba/private/passdb.tdb"
        if command -v pdbedit >/dev/null 2>&1; then
            # Remove configured samba user
            pdbedit -x "${DEFAULT_SAMBA_USER}" 2>/dev/null || true
        fi
    fi

    # Note: We don't remove the samba packages as they might be used by other services

    log_success "Samba module uninstalled successfully"
}

main "$@"