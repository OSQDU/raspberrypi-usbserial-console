#!/bin/bash
# modules/tftp/install.sh - TFTP server setup

source "../../lib/common.sh"

main() {
    log_info "Installing TFTP module..."

    # Validate module files exist
    validate_module_files

    # Deploy configuration
    deploy_tftp_config

    # Configure TFTP permissions
    configure_tftp_permissions

    # Configure TFTP service
    configure_tftp_service

    log_success "TFTP module installed successfully"
}

validate_module_files() {
    local required_files=(
        "templates/tftpd-hpa.conf.template"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            log_error "Required module file not found: ${file}"
            exit 1
        fi
    done

    log_debug "All module files validated"
}

deploy_tftp_config() {
    log_info "Deploying TFTP configuration..."

    # Deploy configuration file from template
    backup_file "/etc/default/tftpd-hpa"
    
    if ! process_template "templates/tftpd-hpa.conf.template" "/etc/default/tftpd-hpa" \
        "SHARED_DIR" "${SHARED_DIR}"; then
        log_error "Failed to deploy TFTP configuration from template"
        return 1
    fi

    # Set proper permissions
    chmod 644 /etc/default/tftpd-hpa
}

configure_tftp_permissions() {
    log_info "Configuring TFTP permissions..."

    # Add tftp user to upload group (created by shared module)
    if ! usermod -a -G upload tftp; then
        log_error "Failed to add tftp to upload group"
        return 1
    fi

    # Test tftp write access to uploadonly directory
    if ! su -s /bin/sh tftp -c "touch ${SHARED_DIR}/uploadonly/.tftp-test" 2>/dev/null; then
        log_error "tftp user cannot write to ${SHARED_DIR}/uploadonly"
        return 1
    else
        rm -f "${SHARED_DIR}/uploadonly/.tftp-test"
        log_info "Verified tftp write access to ${SHARED_DIR}/uploadonly"
    fi

    log_info "TFTP will serve files from: ${SHARED_DIR}"
    log_info "TFTP uploads will go to: ${SHARED_DIR}/uploadonly"
}

configure_tftp_service() {
    log_info "Configuring TFTP service..."

    # Enable but don't start yet (will be handled by service coordination)
    manage_service enable tftpd-hpa
}

main "$@"
