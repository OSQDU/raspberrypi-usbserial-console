#!/bin/bash
# modules/system/install.sh - System preparation and validation

source "../../lib/common.sh"

main() {
    log_info "Installing system module..."

    # Update package database
    log_info "Updating package database..."
    apt-get update -qq

    # Install essential packages
    local essential_packages=(
        "curl"
        "wget"
        "git"
        "vim"
        "htop"
        "tmux"
        "acl"
        "udev"
    )

    for package in "${essential_packages[@]}"; do
        install_package "$package"
    done

    # Create project directories
    create_config_dirs

    # Set up log rotation
    create_logrotate_config

    # Configure basic system settings
    configure_system_settings

    log_success "System module installed successfully"
}

create_logrotate_config() {
    log_info "Setting up log rotation..."

    # Process and deploy logrotate template
    if ! process_template \
        "templates/logrotate.conf" \
        "/etc/logrotate.d/usbserial" \
        "LOG_DIR" "${LOG_DIR}"; then
        log_error "Failed to create logrotate configuration"
        return 1
    fi

    # Set proper permissions
    chmod 644 /etc/logrotate.d/usbserial
}

configure_system_settings() {
    log_info "Configuring system settings..."

    # Enable SSH (if not already enabled)
    systemctl enable ssh

    # Configure timezone to UTC (consistent for logs)
    timedatectl set-timezone UTC

    # Set hostname
    local new_hostname="usbserial-console"
    hostnamectl set-hostname "$new_hostname"

    # Update /etc/hosts
    sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts

    log_info "System hostname set to: $new_hostname"
}

main "$@"
