#!/bin/bash
# Setup unified shared directory for HTTP, TFTP, and SMB file sharing
# Designed for fresh Raspberry Pi OS installations

set -euo pipefail

readonly SHARED_DIR="/srv/shared"

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

create_shared_directory() {
    log "Creating unified shared directory: $SHARED_DIR"
    
    # Create directory structure
    mkdir -p "$SHARED_DIR"/{uploads,downloads,firmware,configs,logs}
    
    # Set appropriate ownership and permissions
    chown -R pi:pi "$SHARED_DIR"
    chmod -R 755 "$SHARED_DIR"
    
    # Make uploads directory writable for web uploads
    chmod 775 "$SHARED_DIR"/uploads
    
    # Create welcome file
    cat > "$SHARED_DIR/README.txt" << 'EOF'
USB Serial Console - Shared File Directory
==========================================

This directory is accessible via multiple protocols:

HTTP/Web:  http://192.168.44.1/
TFTP:      tftp://192.168.44.1/
SMB/CIFS:  \\192.168.44.1\shared

Subdirectories:
- uploads/   - Upload files here
- downloads/ - Download files from here  
- firmware/  - Device firmware files
- configs/   - Configuration backups
- logs/      - Log files

Usage Examples:
- Web browser: Navigate to http://192.168.44.1/
- TFTP upload: tftp 192.168.44.1 -c put myfile.bin
- SMB mount:   sudo mount -t cifs //192.168.44.1/shared /mnt/usb

Generated: $(date)
EOF
    
    log "Shared directory created successfully"
}

setup_nginx_permissions() {
    log "Setting up nginx upload permissions..."
    
    # Create temporary upload directory for nginx
    mkdir -p /tmp/nginx_upload
    chown www-data:www-data /tmp/nginx_upload
    chmod 755 /tmp/nginx_upload
    
    # Ensure www-data can write to uploads directory
    chgrp www-data "$SHARED_DIR/uploads"
    chmod g+w "$SHARED_DIR/uploads"
}

setup_tftp_permissions() {
    log "Setting up TFTP permissions..."
    
    # Add tftp user to pi group for shared access
    usermod -a -G pi tftp 2>/dev/null || true
    
    # Make sure TFTP can write to shared directory
    chmod g+w "$SHARED_DIR"
    
    # Set ACL if available for more granular control
    setfacl -m u:tftp:rwx "$SHARED_DIR" 2>/dev/null || true
}

setup_samba_permissions() {
    log "Setting up Samba permissions..."
    
    # Add pi user to samba with default password
    echo -e "raspberry\nraspberry" | smbpasswd -a pi -s
    
    # Ensure samba can access the directory
    chmod o+rx "$SHARED_DIR"
}

show_access_info() {
    local ip_addr="192.168.44.1"  # Static IP for the access point
    
    cat << EOF

=== Unified File Sharing Setup Complete ===

Shared Directory: $SHARED_DIR

Access Methods:
1. HTTP/Web Browser:
   URL: http://$ip_addr/
   Upload: http://$ip_addr/upload/

2. TFTP:
   Upload: tftp $ip_addr -c put filename
   Download: tftp $ip_addr -c get filename

3. SMB/CIFS:
   Windows: \\\\$ip_addr\\shared
   Linux: sudo mount -t cifs //$ip_addr/shared /mnt/point
   macOS: smb://$ip_addr/shared

Default Credentials:
- SMB Username: pi
- SMB Password: raspberry

Directory Structure:
$SHARED_DIR/
├── uploads/     (file uploads)
├── downloads/   (file downloads)
├── firmware/    (device firmware)
├── configs/     (configuration backups)
├── logs/        (log files)
└── README.txt   (access instructions)

EOF
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        log "Please run: sudo $0"
        exit 1
    fi
    
    log "Setting up unified file sharing directory on fresh Pi OS..."
    
    create_shared_directory
    setup_nginx_permissions
    setup_tftp_permissions
    setup_samba_permissions
    
    show_access_info
    
    log "Setup completed successfully!"
}

main "$@"
