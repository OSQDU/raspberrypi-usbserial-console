USB Serial Console - Shared File Directory
==========================================

This directory is accessible via multiple protocols:

HTTP/Web:  http://{{WIFI_IPV4_GATEWAY}}/
TFTP:      tftp://{{WIFI_IPV4_GATEWAY}}/
SMB/CIFS:  \\{{WIFI_IPV4_GATEWAY}}\shared

Subdirectories:
- uploads/   - Upload files here
- downloads/ - Download files from here  
- firmware/  - Device firmware files
- configs/   - Configuration backups
- logs/      - Log files

Usage Examples:
- Web browser: Navigate to http://{{WIFI_IPV4_GATEWAY}}/
- TFTP upload: tftp {{WIFI_IPV4_GATEWAY}} -c put myfile.bin
- SMB mount:   sudo mount -t cifs //{{WIFI_IPV4_GATEWAY}}/shared /mnt/usb

Generated: {{CURRENT_DATE}}