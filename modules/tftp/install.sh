#!/bin/bash
# modules/tftp/install.sh - TFTP server setup

source "../../lib/common.sh"

main() {
    log_info "Installing TFTP module..."
    
    # Deploy configuration
    deploy_tftp_config
    
    # Configure TFTP service
    configure_tftp_service
    
    log_success "TFTP module installed successfully"
}

deploy_tftp_config() {
    log_info "Deploying TFTP configuration..."
    
    # Deploy configuration file
    backup_file "/etc/default/tftpd-hpa"
    replace_file "tftpd-hpa.conf" "/etc/default/tftpd-hpa"
    
    # Set proper permissions
    chmod 644 /etc/default/tftpd-hpa
    
    # Ensure shared directory exists and has proper permissions for TFTP
    mkdir -p /srv/shared
    chown tftp:tftp /srv/shared 2>/dev/null || true
    chmod 755 /srv/shared
}

configure_tftp_service() {
    log_info "Configuring TFTP service..."
    
    # Enable but don't start yet (will be handled by service coordination)
    manage_service enable tftpd-hpa
}

main "$@"