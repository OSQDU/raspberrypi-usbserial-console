#!/bin/bash
# modules/nginx/install.sh - HTTP file server setup

set -euo pipefail

# Source common functions with validation
if [[ ! -f "../../lib/common.sh" ]]; then
    echo "ERROR: Cannot find common.sh library" >&2
    exit 1
fi

source "../../lib/common.sh"

# Module-specific error handling
nginx_error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "Nginx module installation failed: ${msg}"
    cleanup_on_error
    exit "${code}"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial nginx installation..."

    # Stop and disable service
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true

    # Remove installed files
    rm -f /etc/nginx/sites-available/usbserial
    rm -f /etc/nginx/sites-enabled/usbserial
    rm -f /srv/shared/upload.html

    log_info "Nginx cleanup completed"
}

# Validate module files exist
validate_module_files() {
    local required_files=(
        "fileserver.conf"
        "upload.html"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            nginx_error_exit "Required module file not found: ${file}"
        fi

        if [[ ! -r "${file}" ]]; then
            nginx_error_exit "Required module file not readable: ${file}"
        fi
    done

    log_debug "All module files validated"
}

main() {
    log_info "Installing nginx module..."

    # Validate module files exist
    validate_module_files

    # Deploy configuration
    deploy_nginx_config || nginx_error_exit "Failed to deploy nginx configuration"

    # Configure nginx service
    configure_nginx_service || nginx_error_exit "Failed to configure nginx service"

    log_success "Nginx module installed successfully"
}

deploy_nginx_config() {
    log_info "Deploying nginx configuration..."

    # Validate source files
    if [[ ! -f "fileserver.conf" ]]; then
        log_error "Source nginx configuration not found: fileserver.conf"
        return 1
    fi

    # Create nginx directories if they don't exist
    if ! mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled; then
        log_error "Failed to create nginx directories"
        return 1
    fi

    # Backup default site if it exists
    backup_file "/etc/nginx/sites-available/default"

    # Deploy main site configuration
    if ! replace_file "fileserver.conf" "/etc/nginx/sites-available/usbserial"; then
        log_error "Failed to deploy nginx site configuration"
        return 1
    fi

    # Set proper permissions
    if ! chmod 644 /etc/nginx/sites-available/usbserial; then
        log_error "Failed to set permissions on nginx site config"
        return 1
    fi

    # Enable the site
    if ! ln -sf "/etc/nginx/sites-available/usbserial" "/etc/nginx/sites-enabled/usbserial"; then
        log_error "Failed to enable nginx site"
        return 1
    fi

    # Disable default site
    rm -f "/etc/nginx/sites-enabled/default"

    # Deploy upload interface
    if ! deploy_upload_interface; then
        log_error "Failed to deploy upload interface"
        return 1
    fi

    # Test nginx configuration
    if command -v nginx >/dev/null 2>&1; then
        if ! nginx -t 2>/dev/null; then
            log_error "Nginx configuration test failed"
            return 1
        fi
    else
        log_warn "nginx command not found, skipping configuration test"
    fi

    log_info "Nginx configuration deployed successfully"
}

deploy_upload_interface() {
    log_info "Deploying upload interface..."

    # Validate source file
    if [[ ! -f "upload.html" ]]; then
        log_error "Upload interface file not found: upload.html"
        return 1
    fi

    # Ensure shared directory exists
    if ! mkdir -p /srv/shared; then
        log_error "Failed to create shared directory"
        return 1
    fi

    # Copy upload HTML file to shared directory
    if ! cp "upload.html" "/srv/shared/"; then
        log_error "Failed to copy upload.html to shared directory"
        return 1
    fi

    # Set proper permissions
    if ! chmod 644 /srv/shared/upload.html; then
        log_error "Failed to set permissions on upload.html"
        return 1
    fi

    # Set proper ownership (may fail if www-data doesn't exist yet)
    if ! chown www-data:www-data /srv/shared/upload.html 2>/dev/null; then
        log_warn "Could not set ownership of upload.html (www-data user may not exist yet)"
        # Set safe fallback permissions
        chmod 644 /srv/shared/upload.html
    fi

    log_info "Upload interface deployed successfully"
    log_info "Upload interface will be available at: http://192.168.44.1/upload.html"
}

configure_nginx_service() {
    log_info "Configuring nginx service..."

    # Validate nginx configuration exists
    if [[ ! -f "/etc/nginx/sites-available/usbserial" ]]; then
        log_error "Nginx site configuration not found"
        return 1
    fi

    # Enable but don't start yet (will be handled by service coordination)
    if ! manage_service enable nginx; then
        log_error "Failed to enable nginx service"
        return 1
    fi

    log_info "Nginx service configured successfully"
}

main "$@"
