#!/bin/bash
# Setup unified shared directory for HTTP, TFTP, and SMB file sharing
# Designed for fresh Raspberry Pi OS installations

set -euo pipefail

# Load global configuration
if [[ -f "../../config/global.conf" ]]; then
    source "../../config/global.conf"
else
    # Fallback defaults
    export SHARED_DIR="/srv/shared"
    export WIFI_IPV4_GATEWAY="192.168.44.1"
    export DEFAULT_SAMBA_USER="pi"
    export DEFAULT_SAMBA_PASSWORD="raspberry"
fi

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

create_shared_directory() {
    log "Creating unified shared directory: ${SHARED_DIR}"

    # Create upload group if it doesn't exist
    if ! getent group upload >/dev/null 2>&1; then
        groupadd upload
        log "Created upload group"
    fi

    # Create directory structure
    mkdir -p "${SHARED_DIR}"/{uploadonly,downloads,firmware,configs,logs}

    # Set base directory ownership and permissions
    chown "${DEFAULT_SAMBA_USER}:${DEFAULT_SAMBA_USER}" "${SHARED_DIR}"
    chmod 755 "${SHARED_DIR}"

    # Set subdirectory permissions
    chmod 755 "${SHARED_DIR}"/{downloads,firmware,configs,logs}

    # Set uploadonly directory with shared group ownership
    chown root:upload "${SHARED_DIR}/uploadonly"
    chmod 775 "${SHARED_DIR}/uploadonly"

    # Create welcome file from template
    if [[ -f "templates/README.txt" ]]; then
        sed -e "s|{{WIFI_IPV4_GATEWAY}}|${WIFI_IPV4_GATEWAY}|g" \
            -e "s|{{CURRENT_DATE}}|$(date)|g" \
            "templates/README.txt" > "${SHARED_DIR}/README.txt"
    else
        log "Warning: README template not found, creating basic file"
        echo "USB Serial Console - Shared Directory" > "${SHARED_DIR}/README.txt"
        echo "Generated: $(date)" >> "${SHARED_DIR}/README.txt"
    fi

    log "Shared directory created successfully"
}


show_access_info() {
    echo ""

    if [[ -f "templates/access-info.txt" ]]; then
        sed -e "s|{{SHARED_DIR}}|${SHARED_DIR}|g" \
            -e "s|{{WIFI_IPV4_GATEWAY}}|${WIFI_IPV4_GATEWAY}|g" \
            -e "s|{{DEFAULT_SAMBA_USER}}|${DEFAULT_SAMBA_USER}|g" \
            -e "s|{{DEFAULT_SAMBA_PASSWORD}}|${DEFAULT_SAMBA_PASSWORD}|g" \
            "templates/access-info.txt"
    else
        log "Warning: Access info template not found"
        echo "=== Unified File Sharing Setup Complete ==="
        echo "Shared Directory: ${SHARED_DIR}"
        echo "Access via: http://${WIFI_IPV4_GATEWAY}/"
    fi

    echo ""
}

main() {
    if [[ ${EUID} -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        log "Please run: sudo $0"
        exit 1
    fi

    log "Setting up unified file sharing directory on fresh Pi OS..."

    create_shared_directory

    show_access_info

    log "Setup completed successfully!"
}

main "$@"
