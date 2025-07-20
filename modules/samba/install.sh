#!/bin/bash
# modules/samba/install.sh - SMB/CIFS file sharing setup

source "../../lib/common.sh"

main() {
    log_info "Installing Samba module..."
    
    # Deploy configuration
    deploy_samba_config
    
    # Configure Samba users
    configure_samba_users
    
    # Configure Samba service
    configure_samba_service
    
    log_success "Samba module installed successfully"
}

deploy_samba_config() {
    log_info "Deploying Samba configuration..."
    
    # Backup and deploy configuration
    backup_file "/etc/samba/smb.conf"
    replace_file "smb.conf" "/etc/samba/smb.conf"
    
    # Set proper permissions
    chmod 644 /etc/samba/smb.conf
    
    # Test Samba configuration
    testparm -s /etc/samba/smb.conf >/dev/null || error_exit "Samba configuration test failed"
}

configure_samba_users() {
    log_info "Configuring Samba users..."
    
    # Add pi user to Samba with default password
    if ! pdbedit -L 2>/dev/null | grep -q "^pi:"; then
        log_info "Adding pi user to Samba..."
        echo -e "raspberry\nraspberry" | smbpasswd -a pi -s
    else
        log_info "Samba user 'pi' already exists"
    fi
    
    # Ensure shared directory has proper permissions
    mkdir -p /srv/shared
    chown pi:pi /srv/shared
    chmod 755 /srv/shared
}

configure_samba_service() {
    log_info "Configuring Samba service..."
    
    # Enable services but don't start yet (will be handled by service coordination)
    manage_service enable smbd
    manage_service enable nmbd
}

main "$@"