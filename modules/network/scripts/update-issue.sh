#!/bin/bash
# Update /etc/issue.d/IP.issue with current network information

set -euo pipefail

# Create issue directory if it doesn't exist
mkdir -p /etc/issue.d

# Function to get interface IP
get_interface_ip() {
    local interface="$1"
    local version="$2"  # 4 or 6

    if [[ ! -d "/sys/class/net/${interface}" ]]; then
        echo "not available"
        return
    fi

    local ip
    if [[ "${version}" == "4" ]]; then
        ip=$(ip -4 addr show "${interface}" 2>/dev/null | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | head -n1 || echo "")
    else
        ip=$(ip -6 addr show "${interface}" 2>/dev/null | grep inet6 | grep -v "::1" | grep -v "fe80" | awk '{print $2}' | head -n1 || echo "")
    fi

    if [[ -n "${ip}" ]]; then
        echo "${ip}"
    else
        echo "not assigned"
    fi
}

# Function to get default gateway
get_default_gateway() {
    local version="$1"  # 4 or 6

    local gateway
    if [[ "${version}" == "4" ]]; then
        gateway=$(ip route show default 2>/dev/null | awk '{print $3}' | head -n1 || echo "")
    else
        gateway=$(ip -6 route show default 2>/dev/null | awk '{print $3}' | head -n1 || echo "")
    fi

    if [[ -n "${gateway}" ]]; then
        echo "${gateway}"
    else
        echo "none"
    fi
}

# Get network information
eth0_ipv4=$(get_interface_ip "eth0" "4")
eth0_ipv6=$(get_interface_ip "eth0" "6")
wlan0_ipv4=$(get_interface_ip "wlan0" "4")
wlan0_ipv6=$(get_interface_ip "wlan0" "6")
gateway_ipv4=$(get_default_gateway "4")
gateway_ipv6=$(get_default_gateway "6")

# Generate the issue file
cat > /etc/issue.d/IP.issue << EOF
================================================================================
Network Interfaces:
  eth0  IPv4: ${eth0_ipv4}    IPv6: ${eth0_ipv6}
  wlan0 IPv4: ${wlan0_ipv4}   IPv6: ${wlan0_ipv6}

Routing:
  IPv4 Gateway: ${gateway_ipv4}
  IPv6 Gateway: ${gateway_ipv6}
================================================================================

EOF