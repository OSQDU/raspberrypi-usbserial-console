#!/bin/bash
# modules/network/install.sh - Network configuration setup

set -euo pipefail

# Source common functions with validation
if [[ ! -f "../../lib/common.sh" ]]; then
    echo "ERROR: Cannot find common.sh library" >&2
    exit 1
fi

source "../../lib/common.sh"

# Module-specific error handling
network_error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "Network module installation failed: $msg"
    cleanup_on_error
    exit "$code"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial installation..."

    # Stop and disable services that might have been started
    systemctl stop setup-nat 2>/dev/null || true
    systemctl disable setup-nat 2>/dev/null || true

    # Remove installed files
    rm -f /etc/systemd/system/setup-nat.service
    rm -f /usr/local/bin/configure-nat
    rm -rf /usr/local/share/usbserial/templates
    rm -f /etc/dhcpcd.exit-hooks.d/usb-serial-console

    # Reload systemd
    systemctl daemon-reload 2>/dev/null || true

    log_info "Cleanup completed"
}

# Validate module files exist
validate_module_files() {
    local required_files=(
        "templates/nftables.conf.template"
        "templates/setup-nat.service"
        "templates/dhcpcd-ipv6.conf"
        "templates/networkmanager/99-unmanage-wlan0.conf"
        "templates/networkmanager/99-disable-dnsmasq.conf"
        "templates/update-issue.service"
        "templates/update-issue.timer"
        "scripts/configure-nat.sh"
        "scripts/dhcpcd-hooks.sh"
        "scripts/update-issue.sh"
        "10-router.conf"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            network_error_exit "Required module file not found: $file"
        fi

        if [[ ! -r "$file" ]]; then
            network_error_exit "Required module file not readable: $file"
        fi
    done

    log_debug "All module files validated"
}

main() {
    log_info "Installing network module..."

    # Validate module files exist
    validate_module_files

    # Configure IP forwarding
    configure_ip_forwarding || network_error_exit "Failed to configure IP forwarding"

    # Configure NAT routing
    configure_nat_routing || network_error_exit "Failed to configure NAT routing"

    # Configure NetworkManager
    configure_network_manager || network_error_exit "Failed to configure NetworkManager"

    # Setup dynamic issue file updates
    setup_issue_updates || network_error_exit "Failed to setup issue file updates"

    log_success "Network module installed successfully"
}

configure_ip_forwarding() {
    log_info "Configuring IP forwarding..."

    # Validate source file
    if [[ ! -f "10-router.conf" ]]; then
        log_error "Source sysctl config not found: 10-router.conf"
        return 1
    fi

    # Deploy sysctl configuration
    backup_file "/etc/sysctl.d/10-router.conf"
    if ! replace_file "10-router.conf" "/etc/sysctl.d/10-router.conf"; then
        log_error "Failed to deploy sysctl configuration"
        return 1
    fi

    # Set proper permissions
    chmod 644 "/etc/sysctl.d/10-router.conf"

    # Apply immediately with error handling
    if ! sysctl -p /etc/sysctl.d/10-router.conf >/dev/null 2>&1; then
        log_warn "Failed to apply sysctl settings immediately (will apply on reboot)"
    fi

    # Verify settings are applied
    local ipv4_forward ipv6_forward
    ipv4_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo "0")

    if [[ "$ipv4_forward" == "1" ]] && [[ "$ipv6_forward" == "1" ]]; then
        log_info "IP forwarding enabled for IPv4 and IPv6"
    else
        log_warn "IP forwarding settings may not be active yet (will apply on reboot)"
    fi
}

configure_nat_routing() {
    log_info "Configuring dynamic NAT routing with nftables..."

    # Install required packages
    install_package nftables

    # Create template directory
    mkdir -p /usr/local/share/usbserial/templates

    # Deploy templates
    cp "templates/nftables.conf.template" "/usr/local/share/usbserial/templates/"

    # Deploy scripts
    cp "scripts/configure-nat.sh" "/usr/local/bin/configure-nat"
    chmod +x /usr/local/bin/configure-nat

    # Deploy systemd service from template
    cp "templates/setup-nat.service" "/etc/systemd/system/"

    # Install DHCPv6-PD hooks
    install_dhcpv6_hooks

    # Enable services
    systemctl daemon-reload
    systemctl enable nftables
    systemctl enable setup-nat

    log_info "Dynamic NAT routing configured"
}

install_dhcpv6_hooks() {
    log_info "Installing DHCPv6-PD hooks..."

    # Validate source files
    if [[ ! -f "scripts/dhcpcd-hooks.sh" ]]; then
        log_error "DHCPv6 hook script not found"
        return 1
    fi

    if [[ ! -f "templates/dhcpcd-ipv6.conf" ]]; then
        log_error "DHCPv6 configuration template not found"
        return 1
    fi

    # Create dhcpcd hooks directory
    if ! mkdir -p /etc/dhcpcd.exit-hooks.d; then
        log_error "Failed to create dhcpcd hooks directory"
        return 1
    fi

    # Install the hook script
    if ! cp "scripts/dhcpcd-hooks.sh" "/etc/dhcpcd.exit-hooks.d/usb-serial-console"; then
        log_error "Failed to install DHCPv6 hook script"
        return 1
    fi

    # Set proper permissions
    chmod +x /etc/dhcpcd.exit-hooks.d/usb-serial-console

    # Backup dhcpcd.conf before modification
    backup_file "/etc/dhcpcd.conf"

    # Configure dhcpcd for DHCPv6-PD using template
    if ! grep -q "# USB Serial Console DHCPv6" /etc/dhcpcd.conf 2>/dev/null; then
        {
            echo ""
            cat "templates/dhcpcd-ipv6.conf"
        } >> /etc/dhcpcd.conf || {
            log_error "Failed to update dhcpcd configuration"
            return 1
        }

        # Validate dhcpcd configuration
        if command -v dhcpcd >/dev/null 2>&1; then
            if ! dhcpcd -t 2>/dev/null; then
                log_warn "dhcpcd configuration validation failed"
            fi
        fi

        # Restart dhcpcd to apply new configuration
        if systemctl is-active --quiet dhcpcd; then
            if ! systemctl restart dhcpcd; then
                log_warn "Failed to restart dhcpcd service"
            else
                log_info "dhcpcd service restarted successfully"
            fi
        fi
    else
        log_info "DHCPv6 configuration already present in dhcpcd.conf"
    fi

    log_info "DHCPv6-PD hooks installed successfully"
}

configure_network_manager() {
    log_info "Configuring NetworkManager for hostapd compatibility..."

    # Check for active SSH connections via WiFi
    check_ssh_wifi_warning

    # Create NetworkManager config directory
    mkdir -p /etc/NetworkManager/conf.d

    # Deploy NetworkManager configurations from templates
    cp "templates/networkmanager/99-unmanage-wlan0.conf" "/etc/NetworkManager/conf.d/"
    cp "templates/networkmanager/99-disable-dnsmasq.conf" "/etc/NetworkManager/conf.d/"

    # Reload NetworkManager configuration
    systemctl reload NetworkManager 2>/dev/null || true

    log_info "NetworkManager configured for AP mode compatibility"
}

check_ssh_wifi_warning() {
    # Check for active SSH connections over wireless interfaces
    local ssh_via_wifi=false
    local ssh_connections=""

    # Get all active SSH connections
    ssh_connections=$(ss -tn state established '( dport = :ssh or sport = :ssh )' 2>/dev/null || true)

    if [[ -n "$ssh_connections" ]]; then
        # Check each connection to see if it's over a wireless interface
        while read -r line; do
            if [[ "$line" =~ ESTAB ]]; then
                # Extract local IP from the connection
                local_ip=$(echo "$line" | awk '{print $4}' | cut -d: -f1)

                # Find which interface this IP belongs to
                interface=$(ip route get "$local_ip" 2>/dev/null | grep -o 'dev [^ ]*' | cut -d' ' -f2 || echo "")

                # Check if it's a wireless interface
                if [[ -n "$interface" ]] && [[ -d "/sys/class/net/$interface/wireless" ]]; then
                    ssh_via_wifi=true
                    break
                fi
            fi
        done <<< "$ssh_connections"
    fi

    if [[ "$ssh_via_wifi" == "true" ]]; then
        log_warn "WARNING: Active SSH connection detected via wireless interface"
        log_warn "Configuring NetworkManager will disrupt this SSH session"
        log_warn "It's recommended to connect via Ethernet before proceeding"
        echo
        echo "Options:"
        echo "  1. Stop installation and connect via Ethernet"
        echo "  2. Continue anyway (will likely disconnect this SSH session)"
        echo
        read -p "Enter choice (1/2): " choice

        case "$choice" in
            1)
                log_info "Installation stopped. Please connect via Ethernet and restart."
                exit 0
                ;;
            2)
                log_warn "Continuing - this SSH session will likely be disconnected"
                sleep 3
                ;;
            *)
                log_error "Invalid choice. Stopping installation."
                exit 1
                ;;
        esac
    fi
}

setup_issue_updates() {
    log_info "Setting up dynamic issue file updates..."

    # Deploy the update script
    cp "scripts/update-issue.sh" "/usr/local/bin/update-issue"
    chmod +x /usr/local/bin/update-issue

    # Deploy systemd service and timer
    cp "templates/update-issue.service" "/etc/systemd/system/"
    cp "templates/update-issue.timer" "/etc/systemd/system/"

    # Enable and start the timer
    systemctl daemon-reload
    systemctl enable update-issue.timer
    systemctl start update-issue.timer

    # Run once immediately to populate the file
    /usr/local/bin/update-issue

    log_info "Dynamic issue file updates configured"
}

main "$@"
