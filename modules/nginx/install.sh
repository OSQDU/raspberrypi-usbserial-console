#!/bin/bash
# modules/nginx/install.sh - HTTP file server setup

source "../../lib/common.sh"

main() {
    log_info "Installing nginx module..."
    
    # Deploy configuration
    deploy_nginx_config
    
    # Configure nginx service
    configure_nginx_service
    
    log_success "Nginx module installed successfully"
}

deploy_nginx_config() {
    log_info "Deploying nginx configuration..."
    
    # Deploy main site configuration
    backup_file "/etc/nginx/sites-available/default"
    replace_file "fileserver.conf" "/etc/nginx/sites-available/usbserial"
    
    # Enable the site
    ln -sf "/etc/nginx/sites-available/usbserial" "/etc/nginx/sites-enabled/usbserial"
    
    # Disable default site
    rm -f "/etc/nginx/sites-enabled/default"
    
    # Set proper permissions
    chmod 644 /etc/nginx/sites-available/usbserial
    
    # Deploy upload interface
    deploy_upload_interface
    
    # Test nginx configuration
    nginx -t || error_exit "Nginx configuration test failed"
}

deploy_upload_interface() {
    log_info "Deploying upload interface..."
    
    # Ensure shared directory exists
    mkdir -p /srv/shared
    
    # Copy upload HTML file to shared directory
    cp "upload.html" "/srv/shared/"
    
    # Set proper permissions
    chmod 644 /srv/shared/upload.html
    chown www-data:www-data /srv/shared/upload.html
    
    log_info "Upload interface available at: http://192.168.44.1/upload.html"
}

configure_nginx_service() {
    log_info "Configuring nginx service..."
    
    # Enable but don't start yet (will be handled by service coordination)
    manage_service enable nginx
}

main "$@"