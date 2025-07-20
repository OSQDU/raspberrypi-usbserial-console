#!/bin/bash
# modules/hostapd/install.sh - WiFi Access Point setup

set -euo pipefail

# Source common functions with validation
if [[ ! -f "../../lib/common.sh" ]]; then
    echo "ERROR: Cannot find common.sh library" >&2
    exit 1
fi

source "../../lib/common.sh"

# Module-specific error handling
hostapd_error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "Hostapd module installation failed: $msg"
    cleanup_on_error
    exit "$code"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial hostapd installation..."
    
    # Stop and disable service
    systemctl stop hostapd 2>/dev/null || true
    systemctl disable hostapd 2>/dev/null || true
    
    # Remove installed files
    rm -f /etc/hostapd/hostapd.wpa_psk
    
    log_info "Hostapd cleanup completed"
}

# Validate module files exist
validate_module_files() {
    local required_files=(
        "hostapd.conf.template"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            hostapd_error_exit "Required module file not found: $file"
        fi
        
        if [[ ! -r "$file" ]]; then
            hostapd_error_exit "Required module file not readable: $file"
        fi
    done
    
    log_debug "All module files validated"
}

main() {
    log_info "Installing hostapd module..."
    
    # Validate module files exist
    validate_module_files
    
    # Package is already installed by module system
    # Deploy configuration
    deploy_hostapd_config || hostapd_error_exit "Failed to deploy hostapd configuration"
    
    # Generate WPA PSK
    generate_wpa_psk || hostapd_error_exit "Failed to generate WPA PSK"
    
    # Configure hostapd service
    configure_hostapd_service || hostapd_error_exit "Failed to configure hostapd service"
    
    log_success "Hostapd module installed successfully"
}

deploy_hostapd_config() {
    log_info "Deploying hostapd configuration..."
    
    # Validate template file
    if [[ ! -f "hostapd.conf.template" ]]; then
        log_error "Template file not found: hostapd.conf.template"
        return 1
    fi
    
    local wifi_interface
    if ! wifi_interface=$(get_wifi_interface); then
        log_error "Failed to determine WiFi interface"
        return 1
    fi
    
    if [[ -z "$wifi_interface" ]]; then
        log_error "WiFi interface is empty"
        return 1
    fi
    
    # Validate WiFi interface exists
    if ! ip link show "$wifi_interface" >/dev/null 2>&1; then
        log_error "WiFi interface $wifi_interface not found"
        return 1
    fi
    
    # Process template
    if ! process_template \
        "hostapd.conf.template" \
        "/etc/hostapd/hostapd.conf" \
        "WIFI_INTERFACE" "$wifi_interface" \
        "COUNTRY_CODE" "${WIFI_COUNTRY_CODE}"; then
        log_error "Failed to process hostapd template"
        return 1
    fi
    
    # Backup existing config
    backup_file "/etc/hostapd/hostapd.conf"
    
    # Set proper permissions
    if ! chmod 644 /etc/hostapd/hostapd.conf; then
        log_error "Failed to set permissions on hostapd.conf"
        return 1
    fi
    
    # Validate configuration
    if command -v hostapd >/dev/null 2>&1; then
        if ! hostapd -d /etc/hostapd/hostapd.conf -t 2>/dev/null; then
            log_warn "hostapd configuration validation failed"
        fi
    fi
    
    log_info "Hostapd configuration deployed successfully"
}

generate_wpa_psk() {
    log_info "Generating WPA PSK..."
    
    local wifi_interface
    if ! wifi_interface=$(get_wifi_interface); then
        log_error "Failed to determine WiFi interface for PSK generation"
        return 1
    fi
    
    if [[ -z "$wifi_interface" ]]; then
        log_error "WiFi interface is empty"
        return 1
    fi
    
    local mac_addr
    if ! mac_addr=$(get_mac_address "$wifi_interface"); then
        log_error "Failed to get MAC address for $wifi_interface"
        return 1
    fi
    
    if [[ -z "$mac_addr" ]]; then
        log_error "Could not determine MAC address for $wifi_interface"
        return 1
    fi
    
    # Validate MAC address format
    if ! [[ "$mac_addr" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$ ]]; then
        log_error "Invalid MAC address format: $mac_addr"
        return 1
    fi
    
    # Clean MAC address (remove colons, convert to uppercase)
    local clean_mac
    clean_mac=$(echo "$mac_addr" | tr -d ':' | tr 'a-f' 'A-F')
    
    if [[ ${#clean_mac} -ne 12 ]]; then
        log_error "Invalid cleaned MAC address length: $clean_mac"
        return 1
    fi
    
    # Create hostapd directory if it doesn't exist
    if ! mkdir -p /etc/hostapd; then
        log_error "Failed to create /etc/hostapd directory"
        return 1
    fi
    
    # Create PSK file
    if ! echo "00:00:00:00:00:00 $clean_mac" > /etc/hostapd/hostapd.wpa_psk; then
        log_error "Failed to create WPA PSK file"
        return 1
    fi
    
    if ! chmod 600 /etc/hostapd/hostapd.wpa_psk; then
        log_error "Failed to set permissions on WPA PSK file"
        return 1
    fi
    
    log_info "WiFi credentials:"
    log_info "  SSID: ${WIFI_SSID}"
    log_info "  Password: $clean_mac"
    
    log_info "WPA PSK generated successfully"
}

configure_hostapd_service() {
    log_info "Configuring hostapd service..."
    
    # Validate hostapd configuration file exists
    if [[ ! -f "/etc/hostapd/hostapd.conf" ]]; then
        log_error "Hostapd configuration file not found"
        return 1
    fi
    
    # Backup default hostapd config
    backup_file "/etc/default/hostapd"
    
    # Point hostapd to our config file
    if [[ -f "/etc/default/hostapd" ]]; then
        if ! sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd; then
            log_error "Failed to update /etc/default/hostapd"
            return 1
        fi
    else
        # Create the file if it doesn't exist
        if ! echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd; then
            log_error "Failed to create /etc/default/hostapd"
            return 1
        fi
    fi
    
    # Set proper permissions
    chmod 644 /etc/default/hostapd
    
    # Enable but don't start yet (will be handled by service coordination)
    if ! manage_service enable hostapd; then
        log_error "Failed to enable hostapd service"
        return 1
    fi
    
    log_info "Hostapd service configured successfully"
}

main "$@"
