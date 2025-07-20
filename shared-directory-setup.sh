#!/bin/bash
# Setup unified shared directory for HTTP, TFTP, and SMB file sharing

set -euo pipefail

readonly SHARED_DIR="/srv/shared"
readonly BACKUP_DIR="/opt/usbserial-backup-$(date +%Y%m%d-%H%M%S)"

log() {
    echo "[$(date '+%H:%M:%S')] $*" >&2
}

create_shared_directory() {
    log "Creating unified shared directory: $SHARED_DIR"
    
    # Create directory structure
    sudo mkdir -p "$SHARED_DIR"/{uploads,downloads,firmware,configs,logs}
    
    # Set appropriate ownership and permissions
    sudo chown -R pi:pi "$SHARED_DIR"
    sudo chmod -R 755 "$SHARED_DIR"
    
    # Make it writable for uploads
    sudo chmod 775 "$SHARED_DIR"/uploads
    
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

migrate_existing_files() {
    log "Migrating files from existing directories..."
    
    # Create backup directory
    sudo mkdir -p "$BACKUP_DIR"
    
    # Migrate from old TFTP directory
    if [[ -d "/srv/tftp" ]] && [[ "$(ls -A /srv/tftp 2>/dev/null)" ]]; then
        log "Backing up and migrating /srv/tftp..."
        sudo cp -r /srv/tftp "$BACKUP_DIR/"
        sudo cp -r /srv/tftp/* "$SHARED_DIR/firmware/" 2>/dev/null || true
    fi
    
    # Migrate from old files directory
    if [[ -d "/srv/files" ]] && [[ "$(ls -A /srv/files 2>/dev/null)" ]]; then
        log "Backing up and migrating /srv/files..."
        sudo cp -r /srv/files "$BACKUP_DIR/"
        sudo cp -r /srv/files/* "$SHARED_DIR/downloads/" 2>/dev/null || true
    fi
    
    # Fix permissions after migration
    sudo chown -R pi:pi "$SHARED_DIR"
    
    log "Migration completed. Backup saved to: $BACKUP_DIR"
}

setup_nginx_upload() {
    log "Setting up nginx upload directories..."
    
    # Create temporary upload directory for nginx
    sudo mkdir -p /tmp/nginx_upload
    sudo chown www-data:www-data /tmp/nginx_upload
    sudo chmod 755 /tmp/nginx_upload
    
    # Ensure www-data can write to uploads directory
    sudo chgrp www-data "$SHARED_DIR/uploads"
    sudo chmod g+w "$SHARED_DIR/uploads"
}

setup_tftp_permissions() {
    log "Setting up TFTP permissions..."
    
    # TFTP user needs read/write access
    sudo usermod -a -G pi tftp 2>/dev/null || true
    
    # Make sure TFTP can write to shared directory
    sudo chmod g+w "$SHARED_DIR"
    sudo setfacl -m u:tftp:rwx "$SHARED_DIR" 2>/dev/null || true
}

setup_samba_permissions() {
    log "Setting up Samba permissions..."
    
    # Add pi user to samba if not already added
    if ! sudo pdbedit -L 2>/dev/null | grep -q "^pi:"; then
        log "Adding pi user to Samba..."
        echo -e "raspberry\nraspberry" | sudo smbpasswd -a pi -s
    fi
    
    # Ensure samba can access the directory
    sudo chmod o+rx "$SHARED_DIR"
}

show_access_info() {
    local ip_addr
    ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "192.168.44.1")
    
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
└── README.txt   (this information)

EOF
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log "This script requires root privileges"
        log "Please run: sudo $0"
        exit 1
    fi
    
    log "Setting up unified file sharing directory..."
    
    create_shared_directory
    migrate_existing_files
    setup_nginx_upload
    setup_tftp_permissions
    setup_samba_permissions
    
    show_access_info
    
    log "Setup completed successfully!"
}

main "$@"