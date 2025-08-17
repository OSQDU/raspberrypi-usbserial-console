#!/bin/bash
# modules/samba/install.sh - SMB/CIFS file sharing setup

set -euo pipefail

# Source common functions with validation
if [[ ! -f "../../lib/common.sh" ]]; then
    echo "ERROR: Cannot find common.sh library" >&2
    exit 1
fi

source "../../lib/common.sh"

# Module-specific error handling
samba_error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "Samba module installation failed: ${msg}"
    cleanup_on_error
    exit "${code}"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial samba installation..."

    # Stop and disable services
    systemctl stop smbd 2>/dev/null || true
    systemctl stop nmbd 2>/dev/null || true
    systemctl disable smbd 2>/dev/null || true
    systemctl disable nmbd 2>/dev/null || true

    log_info "Samba cleanup completed"
}

# Validate module files exist
validate_module_files() {
    local required_files=(
        "templates/smb.conf.template"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            samba_error_exit "Required module file not found: ${file}"
        fi

        if [[ ! -r "${file}" ]]; then
            samba_error_exit "Required module file not readable: ${file}"
        fi
    done

    log_debug "All module files validated"
}

main() {
    log_info "Installing Samba module..."

    # Validate module files exist
    validate_module_files

    # Deploy configuration
    deploy_samba_config || samba_error_exit "Failed to deploy samba configuration"

    # Configure Samba users
    configure_samba_users || samba_error_exit "Failed to configure samba users"

    # Configure Samba service
    configure_samba_service || samba_error_exit "Failed to configure samba service"

    log_success "Samba module installed successfully"
}

deploy_samba_config() {
    log_info "Deploying Samba configuration..."

    # Validate template file
    if [[ ! -f "templates/smb.conf.template" ]]; then
        log_error "Source samba configuration template not found: templates/smb.conf.template"
        return 1
    fi

    # Create samba directory if it doesn't exist
    if ! mkdir -p /etc/samba; then
        log_error "Failed to create /etc/samba directory"
        return 1
    fi

    # Backup existing configuration
    backup_file "/etc/samba/smb.conf"

    # Deploy configuration from template
    if ! process_template "templates/smb.conf.template" "/etc/samba/smb.conf" \
        "WIFI_INTERFACE" "${WIFI_INTERFACE}" \
        "SHARED_DIR" "${SHARED_DIR}" \
        "DEFAULT_SAMBA_USER" "${DEFAULT_SAMBA_USER}"; then
        log_error "Failed to deploy samba configuration from template"
        return 1
    fi

    # Set proper permissions
    if ! chmod 644 /etc/samba/smb.conf; then
        log_error "Failed to set permissions on smb.conf"
        return 1
    fi

    # Test Samba configuration
    if command -v testparm >/dev/null 2>&1; then
        if ! testparm -s /etc/samba/smb.conf >/dev/null 2>&1; then
            log_error "Samba configuration test failed"
            return 1
        fi
    else
        log_warn "testparm command not found, skipping configuration validation"
    fi

    log_info "Samba configuration deployed successfully"
}

configure_samba_users() {
    log_info "Configuring Samba users..."

    # Check if configured user exists on the system
    if ! id "${DEFAULT_SAMBA_USER}" >/dev/null 2>&1; then
        log_error "System user '${DEFAULT_SAMBA_USER}' does not exist"
        return 1
    fi

    # Validate samba commands are available
    if ! command -v pdbedit >/dev/null 2>&1; then
        log_error "pdbedit command not found"
        return 1
    fi

    if ! command -v smbpasswd >/dev/null 2>&1; then
        log_error "smbpasswd command not found"
        return 1
    fi

    # Check if configured user already exists in Samba
    if ! pdbedit -L 2>/dev/null | grep -q "^${DEFAULT_SAMBA_USER}:"; then
        log_info "Adding ${DEFAULT_SAMBA_USER} user to Samba..."

        # Add user with default password (using non-interactive mode)
        if ! echo -e "${DEFAULT_SAMBA_PASSWORD}\n${DEFAULT_SAMBA_PASSWORD}" | smbpasswd -a "${DEFAULT_SAMBA_USER}" -s; then
            log_error "Failed to add ${DEFAULT_SAMBA_USER} user to Samba"
            return 1
        fi

        log_info "Samba user '${DEFAULT_SAMBA_USER}' added successfully"
    else
        log_info "Samba user '${DEFAULT_SAMBA_USER}' already exists"
    fi

    # Ensure shared directory exists and has proper permissions
    if ! mkdir -p "${SHARED_DIR}"; then
        log_error "Failed to create shared directory"
        return 1
    fi

    # Set ownership (may fail if user doesn't exist)
    if ! chown "${DEFAULT_SAMBA_USER}:${DEFAULT_SAMBA_USER}" "${SHARED_DIR}" 2>/dev/null; then
        log_warn "Could not set ownership of ${SHARED_DIR} to ${DEFAULT_SAMBA_USER}:${DEFAULT_SAMBA_USER}"
        # Set safe fallback permissions
        chmod 755 "${SHARED_DIR}"
    else
        chmod 755 "${SHARED_DIR}"
    fi

    log_info "Samba users configured successfully"
}

configure_samba_service() {
    log_info "Configuring Samba service..."

    # Validate samba configuration exists
    if [[ ! -f "/etc/samba/smb.conf" ]]; then
        log_error "Samba configuration file not found"
        return 1
    fi

    # Enable services but don't start yet (will be handled by service coordination)
    if ! manage_service enable smbd; then
        log_error "Failed to enable smbd service"
        return 1
    fi

    if ! manage_service enable nmbd; then
        log_error "Failed to enable nmbd service"
        return 1
    fi

    log_info "Samba services configured successfully"
}

main "$@"
