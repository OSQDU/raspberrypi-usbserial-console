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
    log_error "Network module installation failed: ${msg}"
    cleanup_on_error
    exit "${code}"
}

# Cleanup function for failed installations
cleanup_on_error() {
    log_warn "Cleaning up partial installation..."

    # Remove NetworkManager hotspot connection
    nmcli connection delete "USBSerial-Console" 2>/dev/null || true
    rm -f /etc/NetworkManager/system-connections/USBSerial-Console.nmconnection

    # Stop and disable services that might have been started
    systemctl stop setup-nat 2>/dev/null || true
    systemctl disable setup-nat 2>/dev/null || true

    # Remove installed files
    rm -f /etc/systemd/system/setup-nat.service
    rm -f /usr/local/bin/configure-nat
    rm -rf /usr/local/share/usbserial/templates
    rm -f /etc/dhcpcd.exit-hooks.d/usb-serial-console
    rm -f /etc/NetworkManager/conf.d/99-disable-dnsmasq.conf

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
        "templates/networkmanager/99-disable-dnsmasq.conf"
        "templates/networkmanager/USBSerial-Console.nmconnection"
        "templates/update-issue.service"
        "templates/update-issue.timer"
        "scripts/configure-nat.sh"
        "scripts/dhcpcd-hooks.sh"
        "scripts/update-issue.sh"
        "10-router.conf"
    )

    for file in "${required_files[@]}"; do
        if [[ ! -f "${file}" ]]; then
            network_error_exit "Required module file not found: ${file}"
        fi

        if [[ ! -r "${file}" ]]; then
            network_error_exit "Required module file not readable: ${file}"
        fi
    done

    log_debug "All module files validated"
}

main() {
    log_info "Installing network module with WiFi hotspot..."

    # Validate module files exist
    validate_module_files

    # Configure IP forwarding
    configure_ip_forwarding || network_error_exit "Failed to configure IP forwarding"

    # Configure Wi-Fi country to unblock radio
    configure_wifi_country || network_error_exit "Failed to configure WiFi country"

    # Configure NetworkManager
    configure_network_manager || network_error_exit "Failed to configure NetworkManager"

    # Create WiFi hotspot
    create_wifi_hotspot || network_error_exit "Failed to create WiFi hotspot"

    # Configure NAT routing (after network setup is complete)
    configure_nat_routing || network_error_exit "Failed to configure NAT routing"

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

    if [[ "${ipv4_forward}" == "1" ]] && [[ "${ipv6_forward}" == "1" ]]; then
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

configure_wifi_country() {
    log_info "Configuring Wi-Fi country to unblock radio..."

    # Check if rfkill shows Wi-Fi as blocked
    if rfkill list wifi | grep -q "Soft blocked: yes"; then
        log_info "Wi-Fi radio is soft blocked, configuring country..."
        
        # Set Wi-Fi country using raspi-config nonint
        if command -v raspi-config >/dev/null 2>&1; then
            if ! raspi-config nonint do_wifi_country "${WIFI_COUNTRY_CODE}"; then
                log_warn "Failed to set Wi-Fi country via raspi-config, trying alternative method..."
                
                # Alternative: directly write to wpa_supplicant
                if [[ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
                    cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOF
country=${WIFI_COUNTRY_CODE}
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
                    chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
                else
                    # Update existing file if country not set
                    if ! grep -q "^country=" /etc/wpa_supplicant/wpa_supplicant.conf; then
                        sed -i "1i country=${WIFI_COUNTRY_CODE}" /etc/wpa_supplicant/wpa_supplicant.conf
                    fi
                fi
            fi
        else
            log_warn "raspi-config not found, setting country via wpa_supplicant..."
            
            # Create or update wpa_supplicant config
            if [[ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
                cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOF
country=${WIFI_COUNTRY_CODE}
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
                chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
            else
                # Update existing file if country not set
                if ! grep -q "^country=" /etc/wpa_supplicant/wpa_supplicant.conf; then
                    sed -i "1i country=${WIFI_COUNTRY_CODE}" /etc/wpa_supplicant/wpa_supplicant.conf
                fi
            fi
        fi

        # Unblock Wi-Fi radio
        rfkill unblock wifi 2>/dev/null || true
        
        log_info "Wi-Fi country set to: ${WIFI_COUNTRY_CODE}"
    else
        log_info "Wi-Fi radio is not blocked"
    fi
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
    log_info "Configuring NetworkManager for WiFi hotspot..."

    # Check for active SSH connections via WiFi and get user preference
    local nm_action
    nm_action=$(check_ssh_wifi_warning)

    # Create NetworkManager config directory
    mkdir -p /etc/NetworkManager/conf.d

    # Deploy NetworkManager configurations from templates
    cp "templates/networkmanager/99-disable-dnsmasq.conf" "/etc/NetworkManager/conf.d/"

    # Handle NetworkManager reload based on SSH detection
    case "${nm_action}" in
        "restart_later")
            log_info "NetworkManager configuration deployed (will restart after installation)"
            # Set flag for later restart
            export RESTART_NETWORKMANAGER_LATER="true"
            ;;
        "restart_now")
            log_warn "Restarting NetworkManager now (SSH session may disconnect)"
            systemctl restart NetworkManager 2>/dev/null || true
            log_info "NetworkManager restarted"
            ;;
        "reload_now")
            systemctl reload NetworkManager 2>/dev/null || true
            log_info "NetworkManager configuration reloaded"
            ;;
    esac

    log_info "NetworkManager configured for WiFi hotspot"
}

check_ssh_wifi_warning() {
    # Skip interactive prompt if running non-interactively
    if [[ "${NONINTERACTIVE:-false}" == "true" ]] || [[ ! -t 0 ]]; then
        echo "reload_now"
        return 0
    fi

    # Check for active SSH connections over wireless interfaces
    local ssh_via_wifi=false
    local ssh_connections=""

    # Get all active SSH connections
    ssh_connections=$(ss -tn state established '( dport = :ssh or sport = :ssh )' 2>/dev/null || true)

    if [[ -n "${ssh_connections}" ]]; then
        # Check each connection to see if it's over a wireless interface
        while read -r line; do
            if [[ "${line}" =~ ESTAB ]]; then
                # Extract local IP from the connection
                local_ip=$(echo "${line}" | awk '{print $4}' | cut -d: -f1)

                # Find which interface this IP belongs to
                interface=$(ip route get "${local_ip}" 2>/dev/null | grep -o 'dev [^ ]*' | cut -d' ' -f2 || echo "")

                # Check if it's a wireless interface
                if [[ -n "${interface}" ]] && [[ -d "/sys/class/net/${interface}/wireless" ]]; then
                    ssh_via_wifi=true
                    break
                fi
            fi
        done <<< "${ssh_connections}"
    fi

    if [[ "${ssh_via_wifi}" == "true" ]]; then
        log_warn "WARNING: Active SSH connection detected via wireless interface"
        log_warn "NetworkManager configuration changes may disrupt this SSH session"
        echo
        echo "Options:"
        echo "  1. Stop installation and connect via Ethernet"
        echo "  2. Defer NetworkManager restart until end of installation"
        echo "  3. Continue with immediate restart (may disconnect SSH)"
        echo "  4. Continue with reload only (less disruptive)"
        echo
        read -p "Enter choice (1/2/3/4): " choice

        case "${choice}" in
            1)
                log_info "Installation stopped. Please connect via Ethernet and restart."
                exit 0
                ;;
            2)
                echo "restart_later"
                return 0
                ;;
            3)
                log_warn "Will restart NetworkManager immediately"
                echo "restart_now"
                return 0
                ;;
            4)
                log_info "Will reload NetworkManager configuration only"
                echo "reload_now"
                return 0
                ;;
            *)
                log_error "Invalid choice. Using reload-only as default."
                echo "reload_now"
                return 0
                ;;
        esac
    else
        # No SSH via WiFi detected, safe to reload immediately
        echo "reload_now"
    fi
}

create_wifi_hotspot() {
    log_info "Creating WiFi hotspot using NetworkManager configuration file..."

    local wifi_interface
    if ! wifi_interface=$(get_wifi_interface); then
        log_error "Failed to determine WiFi interface"
        return 1
    fi

    if [[ -z "${wifi_interface}" ]]; then
        log_error "WiFi interface is empty"
        return 1
    fi

    # Validate WiFi interface exists
    if ! ip link show "${wifi_interface}" >/dev/null 2>&1; then
        log_error "WiFi interface ${wifi_interface} not found"
        return 1
    fi

    # Generate WPA PSK from MAC address
    local mac_addr
    if ! mac_addr=$(get_mac_address "${wifi_interface}"); then
        log_error "Failed to get MAC address for ${wifi_interface}"
        return 1
    fi

    if [[ -z "${mac_addr}" ]]; then
        log_error "Could not determine MAC address for ${wifi_interface}"
        return 1
    fi

    # Validate MAC address format
    if ! [[ "${mac_addr}" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$ ]]; then
        log_error "Invalid MAC address format: ${mac_addr}"
        return 1
    fi

    # Clean MAC address (remove colons, convert to uppercase)
    local clean_mac
    clean_mac=$(echo "${mac_addr}" | tr -d ':' | tr 'a-f' 'A-F')

    if [[ ${#clean_mac} -ne 12 ]]; then
        log_error "Invalid cleaned MAC address length: ${clean_mac}"
        return 1
    fi

    # Remove any existing hotspot connections
    nmcli connection delete "USBSerial-Console" 2>/dev/null || true

    # Create NetworkManager connections directory
    mkdir -p /etc/NetworkManager/system-connections

    # Deploy NetworkManager connection file from template
    log_info "Deploying NetworkManager hotspot connection file..."
    
    if ! process_template "templates/networkmanager/USBSerial-Console.nmconnection" \
        "/etc/NetworkManager/system-connections/USBSerial-Console.nmconnection" \
        "WIFI_INTERFACE" "${wifi_interface}" \
        "WIFI_SSID" "${WIFI_SSID}" \
        "WIFI_PASSWORD" "${clean_mac}" \
        "WIFI_IPV4_GATEWAY" "${WIFI_IPV4_GATEWAY}"; then
        log_error "Failed to deploy NetworkManager connection file"
        return 1
    fi

    # Set proper permissions for NetworkManager connection file
    chmod 600 /etc/NetworkManager/system-connections/USBSerial-Console.nmconnection

    # Reload NetworkManager to pick up the new connection
    if ! nmcli connection reload; then
        log_warn "Failed to reload NetworkManager connections"
    fi

    log_info "WiFi hotspot connection configured successfully"
    log_info "  SSID: ${WIFI_SSID}"
    log_info "  Password: ${clean_mac}"
    log_info "  Interface: ${wifi_interface}"
    log_info "  Gateway: ${WIFI_IPV4_GATEWAY}"
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
