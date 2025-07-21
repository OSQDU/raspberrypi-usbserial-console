#!/bin/bash
# modules/dnsmasq/install.sh - DNS and DHCP server setup

set -euo pipefail

# Source common functions with validation
if [[ ! -f "../../lib/common.sh" ]]; then
    echo "ERROR: Cannot find common.sh library" >&2
    exit 1
fi

source "../../lib/common.sh"

# Module-specific error handling
dnsmasq_error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "Dnsmasq module installation failed: $msg"
    cleanup_on_error
    exit "$code"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial dnsmasq installation..."

    # Stop and disable service
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl disable dnsmasq 2>/dev/null || true

    log_info "Dnsmasq cleanup completed"
}

# Validate module files exist
validate_module_files() {
    # Check for either template or static config
    if [[ ! -f "dnsmasq.conf.template" && ! -f "dnsmasq.conf" ]]; then
        dnsmasq_error_exit "Neither dnsmasq.conf.template nor dnsmasq.conf found"
    fi

    # Validate file is readable
    if [[ -f "dnsmasq.conf.template" ]]; then
        if [[ ! -r "dnsmasq.conf.template" ]]; then
            dnsmasq_error_exit "Template file not readable: dnsmasq.conf.template"
        fi
    elif [[ -f "dnsmasq.conf" ]]; then
        if [[ ! -r "dnsmasq.conf" ]]; then
            dnsmasq_error_exit "Config file not readable: dnsmasq.conf"
        fi
    fi

    log_debug "Module files validated"
}

main() {
    log_info "Installing dnsmasq module..."

    # Validate module files exist
    validate_module_files

    # Deploy configuration
    deploy_dnsmasq_config || dnsmasq_error_exit "Failed to deploy dnsmasq configuration"

    # Configure dnsmasq service
    configure_dnsmasq_service || dnsmasq_error_exit "Failed to configure dnsmasq service"

    log_success "Dnsmasq module installed successfully"
}

deploy_dnsmasq_config() {
    log_info "Deploying dnsmasq configuration..."

    local wifi_interface ethernet_interface

    # Get interfaces with error handling
    if ! wifi_interface=$(get_wifi_interface); then
        log_error "Failed to determine WiFi interface"
        return 1
    fi

    if ! ethernet_interface=$(get_ethernet_interface); then
        log_error "Failed to determine Ethernet interface"
        return 1
    fi

    if [[ -z "$wifi_interface" ]]; then
        log_error "WiFi interface is empty"
        return 1
    fi

    if [[ -z "$ethernet_interface" ]]; then
        log_error "Ethernet interface is empty"
        return 1
    fi

    # Validate interfaces exist
    if ! ip link show "$wifi_interface" >/dev/null 2>&1; then
        log_error "WiFi interface $wifi_interface not found"
        return 1
    fi

    if ! ip link show "$ethernet_interface" >/dev/null 2>&1; then
        log_warn "Ethernet interface $ethernet_interface not found (may be okay if not connected)"
    fi

    # Backup existing config
    backup_file "/etc/dnsmasq.conf"

    # Process template if it exists, otherwise use static config
    if [[ -f "dnsmasq.conf.template" ]]; then
        if ! process_template \
            "dnsmasq.conf.template" \
            "/etc/dnsmasq.conf" \
            "WIFI_INTERFACE" "$wifi_interface" \
            "ETHERNET_INTERFACE" "$ethernet_interface"; then
            log_error "Failed to process dnsmasq template"
            return 1
        fi
    else
        # Deploy static config
        if ! replace_file "dnsmasq.conf" "/etc/dnsmasq.conf"; then
            log_error "Failed to deploy dnsmasq configuration"
            return 1
        fi
    fi

    # Set proper permissions
    if ! chmod 644 /etc/dnsmasq.conf; then
        log_error "Failed to set permissions on dnsmasq.conf"
        return 1
    fi

    # Create DHCP lease directory
    if ! mkdir -p /var/lib/dhcp; then
        log_error "Failed to create DHCP lease directory"
        return 1
    fi

    # Set proper ownership (may fail if dnsmasq user doesn't exist yet)
    chown dnsmasq:nogroup /var/lib/dhcp 2>/dev/null || {
        log_warn "Could not set ownership of /var/lib/dhcp (dnsmasq user may not exist yet)"
    }

    # Validate dnsmasq configuration
    if command -v dnsmasq >/dev/null 2>&1; then
        if ! dnsmasq --test 2>/dev/null; then
            log_warn "dnsmasq configuration validation failed"
        fi
    fi

    log_info "Dnsmasq configuration deployed successfully"
}

configure_dnsmasq_service() {
    log_info "Configuring dnsmasq service..."

    # Validate dnsmasq configuration exists
    if [[ ! -f "/etc/dnsmasq.conf" ]]; then
        log_error "Dnsmasq configuration file not found"
        return 1
    fi

    # Enable but don't start yet (will be handled by service coordination)
    if ! manage_service enable dnsmasq; then
        log_error "Failed to enable dnsmasq service"
        return 1
    fi

    log_info "Dnsmasq service configured successfully"
}

main "$@"
