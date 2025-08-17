#!/bin/bash
# modules/shared/uninstall.sh - Shared module cleanup

source "../../lib/common.sh"

main() {
    log_info "Uninstalling shared module..."

    # Remove shared directory (with confirmation)
    if [[ -d "${SHARED_DIR}" ]]; then
        log_warn "This will remove the entire shared directory: ${SHARED_DIR}"
        log_warn "All files in the shared directory will be lost!"
        
        if [[ "${FORCE:-false}" != "true" ]]; then
            read -p "Are you sure you want to continue? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Shared directory removal cancelled"
                return 0
            fi
        fi
        
        # Backup the directory before removal
        backup_file "${SHARED_DIR}"
        rm -rf "${SHARED_DIR}"
        log_info "Shared directory removed: ${SHARED_DIR}"
    fi

    # Remove upload group (only if no users are in it)
    if getent group upload >/dev/null 2>&1; then
        local group_members
        group_members=$(getent group upload | cut -d: -f4)
        
        if [[ -z "${group_members}" ]]; then
            groupdel upload 2>/dev/null || true
            log_info "Removed upload group"
        else
            log_warn "Upload group still has members, not removing: ${group_members}"
        fi
    fi

    # Remove temporary upload directories
    rm -rf /tmp/nginx_uploads

    log_success "Shared module uninstalled successfully"
}

main "$@"