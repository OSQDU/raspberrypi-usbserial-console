#!/bin/bash
# configure-nat.sh - Dynamic NAT and IPv6 configuration

set -euo pipefail

# Load global configuration
if [[ -f "/usr/local/share/usbserial/global.conf" ]]; then
    source "/usr/local/share/usbserial/global.conf"
elif [[ -f "../../../config/global.conf" ]]; then
    source "../../../config/global.conf"
else
    # Fallback defaults
    export WIFI_INTERFACE="wlan0"
    export ETH_INTERFACE="eth0"
    export WIFI_IPV4_NETWORK="192.168.44.0/24"
    export WIFI_IPV6_ULA="2001:db8:44::/64"
    export TEMPLATE_DIR="/usr/local/share/usbserial/templates"
    export MAX_RETRIES=3
    export RETRY_DELAY=2
fi

# Configuration constants using global variables
readonly NFTABLES_TEMPLATE="${NFTABLES_TEMPLATE:-${TEMPLATE_DIR}/nftables.conf.template}"

# Logging with error levels
log() {
    local level="${1:-INFO}"
    local message="$2"
    logger -t "usb-serial-nat" -p "daemon.$level" "$message"
    echo "[$(date '+%H:%M:%S')] [$level] $message" >&2
}

log_info() { log "info" "$1"; }
log_warn() { log "warning" "$1"; }
log_error() { log "err" "$1"; }
log_debug() { log "debug" "$1"; }

# Error handling
error_exit() {
    local msg="$1"
    local code="${2:-1}"
    log_error "$msg"
    exit "$code"
}

# Retry mechanism for network operations
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi

        log_warn "Command failed (attempt $attempt/$max_attempts): $*"
        if [[ $attempt -lt $max_attempts ]]; then
            log_info "Retrying in ${delay}s..."
            sleep "$delay"
        fi
        ((attempt++))
    done

    log_error "Command failed after $max_attempts attempts: $*"
    return 1
}

# Validate interface exists and is up
validate_interface() {
    local interface="$1"
    local required="${2:-false}"

    if ! ip link show "$interface" >/dev/null 2>&1; then
        if [[ "$required" == "true" ]]; then
            error_exit "Required interface $interface not found"
        else
            log_warn "Interface $interface not found"
            return 1
        fi
    fi

    # Check if interface is up
    if ! ip link show "$interface" | grep -q "state UP"; then
        log_warn "Interface $interface is not UP"
        return 1
    fi

    log_debug "Interface $interface validated successfully"
    return 0
}

# Check if command/package is available
check_dependency() {
    local cmd="$1"
    local package="${2:-$cmd}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' not found. Please install package: $package"
        return 1
    fi
    return 0
}

# Validate template file exists and is readable
validate_template() {
    if [[ ! -f "$NFTABLES_TEMPLATE" ]]; then
        error_exit "Template file not found: $NFTABLES_TEMPLATE"
    fi

    if [[ ! -r "$NFTABLES_TEMPLATE" ]]; then
        error_exit "Template file not readable: $NFTABLES_TEMPLATE"
    fi

    log_debug "Template validated: $NFTABLES_TEMPLATE"
}

# Check if eth0 has IPv6 connectivity
check_ipv6_upstream() {
    # Validate eth0 exists first
    if ! validate_interface "$ETH_INTERFACE" false; then
        log_warn "Cannot check IPv6 upstream - $ETH_INTERFACE not available"
        return 1
    fi

    # Check if eth0 has a global IPv6 address
    if ip -6 addr show "$ETH_INTERFACE" 2>/dev/null | grep -q "scope global"; then
        log_info "IPv6 connectivity detected on $ETH_INTERFACE"
        return 0
    else
        log_info "No IPv6 connectivity on $ETH_INTERFACE"
        return 1
    fi
}

# Get DHCPv6-PD prefix if available
get_dhcpv6_prefix() {
    local prefix=""

    # Try to get prefix from dhcpcd lease file
    if [[ -f /var/lib/dhcpcd/dhcpcd.leases ]] && [[ -r /var/lib/dhcpcd/dhcpcd.leases ]]; then
        prefix=$(awk '/^ia_pd/ && /'"$ETH_INTERFACE"'/ {print $3}' /var/lib/dhcpcd/dhcpcd.leases 2>/dev/null | tail -1)
        if [[ -n "$prefix" ]]; then
            log_debug "Found DHCPv6-PD prefix from dhcpcd: $prefix"
        fi
    fi

    # Alternative: check if systemd-networkd is used
    if [[ -z "$prefix" ]] && command -v networkctl >/dev/null 2>&1; then
        prefix=$(networkctl status "$ETH_INTERFACE" 2>/dev/null | awk '/Prefix:/ {print $2}' | head -1)
        if [[ -n "$prefix" ]]; then
            log_debug "Found IPv6 prefix from networkctl: $prefix"
        fi
    fi

    # Alternative: try to extract from ip command
    if [[ -z "$prefix" ]]; then
        # Look for delegated prefixes in routing table
        prefix=$(ip -6 route show dev "$WIFI_INTERFACE" 2>/dev/null | awk '/^[0-9a-f:]+::\// {print $1; exit}')
        if [[ -n "$prefix" ]]; then
            log_debug "Found IPv6 prefix from routing table: $prefix"
        fi
    fi

    # Validate prefix format if found
    if [[ -n "$prefix" ]] && ! [[ "$prefix" =~ ^[0-9a-f:]+/[0-9]+$ ]]; then
        log_warn "Invalid IPv6 prefix format: $prefix"
        prefix=""
    fi

    echo "$prefix"
}

# Configure IPv6 on wlan0
configure_wlan0_ipv6() {
    local prefix="$1"
    local wlan0_addr=""

    # Validate wlan0 interface exists
    if ! validate_interface "$WIFI_INTERFACE" true; then
        error_exit "Cannot configure IPv6 - $WIFI_INTERFACE not available"
    fi

    if [[ -n "$prefix" ]]; then
        # Use delegated prefix - create ::1 address for the gateway
        wlan0_addr="${prefix%::/*}::1/64"
        log_info "Configuring wlan0 with delegated prefix: $wlan0_addr"
    else
        # Use ULA prefix as fallback
        wlan0_addr="${WIFI_IPV6_ULA%/*}::1/64"
        log_info "Using ULA prefix for wlan0: $wlan0_addr"
    fi

    # Validate IPv6 address format
    if ! [[ "$wlan0_addr" =~ ^[0-9a-f:]+/[0-9]+$ ]]; then
        log_error "Invalid IPv6 address format: $wlan0_addr"
        return 1
    fi

    # Remove existing IPv6 addresses (except link-local)
    if ! ip -6 addr flush dev "$WIFI_INTERFACE" scope global 2>/dev/null; then
        log_warn "Failed to flush existing IPv6 addresses on $WIFI_INTERFACE"
    fi

    # Add new IPv6 address with retry
    if retry_command "$MAX_RETRIES" "$RETRY_DELAY" ip -6 addr add "$wlan0_addr" dev "$WIFI_INTERFACE"; then
        log_info "Successfully configured IPv6 address: $wlan0_addr"
    else
        log_error "Failed to configure IPv6 address: $wlan0_addr"
        return 1
    fi

    echo "$wlan0_addr"
}

# Update nftables rules with current IPv6 prefix
update_nftables_rules() {
    local ipv6_prefix="$1"
    local has_ipv6_upstream="$2"

    log "Updating nftables rules with IPv6 prefix: $ipv6_prefix"

    # Prepare template variables
    local ipv6_nat_rule=""
    local ipv6_forward_rule=""
    local ipv6_intra_rule=""

    if [ "$has_ipv6_upstream" = "true" ] && [ -n "$ipv6_prefix" ]; then
        # IPv6 NAT (commented by default as most don't need it)
        ipv6_nat_rule="# ip6 saddr ${ipv6_prefix} oifname \"$ETH_INTERFACE\" masquerade"

        # IPv6 forwarding rules
        ipv6_forward_rule="iifname \"$WIFI_INTERFACE\" oifname \"$ETH_INTERFACE\" ip6 saddr ${ipv6_prefix} accept"
        ipv6_intra_rule="iifname \"$WIFI_INTERFACE\" oifname \"$WIFI_INTERFACE\" ip6 saddr ${ipv6_prefix} accept"
    else
        # No IPv6 rules
        ipv6_nat_rule="# No IPv6 NAT (no upstream IPv6)"
        ipv6_forward_rule="# No IPv6 forwarding (no upstream IPv6)"
        ipv6_intra_rule="# No IPv6 intra-WLAN (no IPv6 prefix)"
    fi

    # Generate nftables config from template
    generate_nftables_config \
        "$WIFI_INTERFACE" \
        "$ETH_INTERFACE" \
        "$WIFI_IPV4_NETWORK" \
        "$ipv6_prefix" \
        "$ipv6_nat_rule" \
        "$ipv6_forward_rule" \
        "$ipv6_intra_rule"

    # Reload nftables
    nft -f /etc/nftables.conf
    log "nftables rules updated"
}

# Generate nftables config from template
generate_nftables_config() {
    local wifi_iface="$1"
    local eth_iface="$2"
    local ipv4_network="$3"
    local ipv6_prefix="$4"
    local ipv6_nat_rule="$5"
    local ipv6_forward_rule="$6"
    local ipv6_intra_rule="$7"

    # Validate template exists
    validate_template

    # Create temporary file for atomic replacement
    local temp_config
    temp_config=$(mktemp /tmp/nftables.conf.XXXXXX) || {
        error_exit "Failed to create temporary file"
    }

    # Ensure cleanup on exit
    trap 'rm -f "$temp_config"' EXIT

    # Read template and substitute variables
    if ! sed -e "s|{{WIFI_INTERFACE}}|$wifi_iface|g" \
            -e "s|{{ETH_INTERFACE}}|$eth_iface|g" \
            -e "s|{{IPV4_NETWORK}}|$ipv4_network|g" \
            -e "s|{{IPV6_PREFIX}}|$ipv6_prefix|g" \
            -e "s|{{IPV6_NAT_RULE}}|$ipv6_nat_rule|g" \
            -e "s|{{IPV6_FORWARD_RULE}}|$ipv6_forward_rule|g" \
            -e "s|{{IPV6_INTRA_RULE}}|$ipv6_intra_rule|g" \
            "$NFTABLES_TEMPLATE" > "$temp_config"; then
        error_exit "Failed to process nftables template"
    fi

    # Validate generated config
    if ! nft -c -f "$temp_config" 2>/dev/null; then
        log_error "Generated nftables configuration is invalid"
        log_debug "Config file: $temp_config"
        return 1
    fi

    # Atomically replace config
    if ! mv "$temp_config" /etc/nftables.conf; then
        error_exit "Failed to install nftables configuration"
    fi

    # Set proper permissions
    chmod 644 /etc/nftables.conf
    log_debug "nftables configuration generated successfully"
}

# Update dnsmasq configuration with new IPv6 prefix
update_dnsmasq_ipv6() {
    local ipv6_prefix="$1"

    if [ -n "$ipv6_prefix" ]; then
        log "Updating dnsmasq with IPv6 prefix: $ipv6_prefix"

        # Extract prefix base (remove ::/<number> suffix)
        local ipv6_prefix_base="${ipv6_prefix%::/*}"

        # Generate dynamic config from template
        if ! sed -e "s|{{WIFI_INTERFACE}}|$WIFI_INTERFACE|g" \
                -e "s|{{IPV6_PREFIX_BASE}}|$ipv6_prefix_base|g" \
                "${TEMPLATE_DIR}/dnsmasq-ipv6-dynamic.conf" > /etc/dnsmasq.d/ipv6-dynamic.conf; then
            log_error "Failed to generate dnsmasq IPv6 configuration"
            return 1
        fi
    else
        # Remove dynamic IPv6 config if no prefix
        rm -f /etc/dnsmasq.d/ipv6-dynamic.conf
    fi

    # Reload dnsmasq
    if systemctl is-active --quiet dnsmasq; then
        systemctl reload dnsmasq
        log "dnsmasq configuration reloaded"
    fi
}

# Main configuration function
main() {
    log_info "Starting NAT and IPv6 routing configuration"

    # Validate dependencies
    check_dependency "nft" "nftables" || error_exit "nftables not available"
    check_dependency "ip" "iproute2" || error_exit "iproute2 not available"

    # Validate required interfaces
    validate_interface "$WIFI_INTERFACE" true

    # Check IPv6 upstream connectivity
    local has_ipv6_upstream="false"
    if check_ipv6_upstream; then
        has_ipv6_upstream="true"
    fi

    # Get DHCPv6-PD prefix
    local dhcpv6_prefix=""
    if [[ "$has_ipv6_upstream" == "true" ]]; then
        dhcpv6_prefix=$(get_dhcpv6_prefix)
        if [[ -n "$dhcpv6_prefix" ]]; then
            log_info "Found DHCPv6-PD prefix: $dhcpv6_prefix"
        else
            log_info "No DHCPv6-PD prefix available"
        fi
    fi

    # Configure wlan0 IPv6
    local wlan0_ipv6
    if ! wlan0_ipv6=$(configure_wlan0_ipv6 "$dhcpv6_prefix"); then
        log_error "Failed to configure IPv6 on $WIFI_INTERFACE"
        return 1
    fi

    # Extract prefix from wlan0 address for firewall rules
    local firewall_prefix=""
    if [[ -n "$wlan0_ipv6" ]]; then
        firewall_prefix="${wlan0_ipv6%::*}::/64"
    fi

    # Update firewall rules
    if ! update_nftables_rules "$firewall_prefix" "$has_ipv6_upstream"; then
        log_error "Failed to update nftables rules"
        return 1
    fi

    # Update dnsmasq if we have a real delegated prefix
    if [[ -n "$dhcpv6_prefix" ]]; then
        if ! update_dnsmasq_ipv6 "$dhcpv6_prefix"; then
            log_warn "Failed to update dnsmasq IPv6 configuration"
        fi
    fi

    log_info "NAT and IPv6 configuration completed successfully"
}

# Handle different invocation modes
case "${1:-configure}" in
    configure)
        main
        ;;
    dhcpv6-hook)
        # Called from dhcpcd hook
        log "DHCPv6-PD event detected, reconfiguring..."
        main
        ;;
    cleanup)
        log "Cleaning up NAT configuration"
        nft flush ruleset 2>/dev/null || true
        rm -f /etc/dnsmasq.d/ipv6-dynamic.conf
        systemctl reload dnsmasq 2>/dev/null || true
        ;;
    *)
        echo "Usage: $0 [configure|dhcpv6-hook|cleanup]"
        exit 1
        ;;
esac
