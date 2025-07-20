# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modern, modular Raspberry Pi network management appliance that provides USB serial console access with supporting network services. The system creates a WiFi hotspot with integrated DNS, DHCP, HTTP file server, TFTP, and SMB services for managing serial devices.

## Architecture

The project uses a **template-based, configuration-driven modular architecture** with:

- **Centralized Configuration**: All settings in `config/global.conf`
- **Template System**: Heredocs extracted to reusable template files
- **Robust Error Handling**: Comprehensive validation and cleanup
- **Dependency Resolution**: Automatic module ordering and validation

```
raspberrypi-usbserial-console/
├── install.sh              # Main installer with dependency resolution
├── config/                 # Centralized configuration
│   └── global.conf         # All configurable variables
├── lib/                    # Shared libraries
│   ├── common.sh           # Common utilities, logging, validation
│   └── modules.sh          # Module management system
└── modules/                # Individual modules with templates
    ├── system/             # System preparation and validation
    │   └── templates/      # Logrotate configuration
    ├── network/            # Network configuration (IPv4/IPv6 NAT, nftables)
    │   ├── scripts/        # NAT configuration, DHCPv6-PD hooks
    │   └── templates/      # nftables, dhcpcd, NetworkManager configs
    ├── hostapd/            # WiFi Access Point (WPA3, 802.11ac)
    │   └── templates/      # hostapd configuration
    ├── dnsmasq/            # DNS/DHCP server (modern DNS, security)
    │   └── templates/      # dnsmasq configuration
    ├── nginx/              # HTTP file server with uploads
    │   └── templates/      # nginx configuration, upload interface
    ├── tftp/               # TFTP server
    ├── samba/              # SMB/CIFS file sharing
    │   └── templates/      # SMB configuration
    ├── udev/               # USB serial device rules (physical port mapping)
    ├── minicom/            # Serial console configuration
    │   └── templates/      # Console access scripts
    ├── services/           # Systemd service coordination
    │   └── templates/      # Service files, startup scripts
    └── shared/             # Unified file sharing setup
        └── templates/      # README, access info
```

## Installation Commands

```bash
# Full installation
sudo ./install.sh

# Install specific modules
sudo ./install.sh system shared udev nginx

# List available modules
./install.sh --list

# Check status
sudo ./install.sh --status

# Force reinstall
sudo ./install.sh --force nginx
```

## Key Features

### **Configuration Management**
- **Centralized Variables**: All settings in `config/global.conf` with environment variable support
- **Template-Based**: Configuration files generated from templates with variable substitution
- **Override Capability**: Variables can be customized via environment or config file editing

### **Network Services**
- **IPv4/IPv6 Dual Stack**: NAT routing with DHCPv6-PD support and automatic prefix delegation
- **Modern Firewall**: nftables-based rules with template-driven configuration
- **Unified File Sharing**: `/srv/shared` accessible via HTTP, TFTP, and SMB protocols
- **Smart WiFi**: WPA3/WPA2 with MAC-based password generation

### **USB Serial Management**
- **Physical Port Mapping**: `/dev/usbserial-X.Y` based on actual USB port locations
- **Multi-Device Support**: Handles both single-port and multi-port USB serial adapters
- **Console Scripts**: `console [device]` and `list-consoles` for easy access
- **Multi-Pi Compatibility**: Supports Pi 3, 4, 5, Zero 2W with automatic USB topology detection

### **System Reliability**
- **Robust Error Handling**: Comprehensive validation, retry mechanisms, and cleanup functions
- **Service Coordination**: Systemd-managed services with proper dependency ordering
- **Automatic Startup**: Services start in correct order with interface detection
- **Logging**: Centralized logging with rotation and structured error reporting

## Default Configuration

All default values are defined in `config/global.conf` and can be easily customized:

```bash
# Network Settings
WIFI_SSID="USBSerial-Console"
WIFI_IPV4_NETWORK="192.168.44.0/24"
WIFI_IPV4_GATEWAY="192.168.44.1"
WIFI_IPV4_DHCP_START="192.168.44.100"
WIFI_IPV4_DHCP_END="192.168.44.200"

# Interfaces
WIFI_INTERFACE="wlan0"
ETH_INTERFACE="eth0"

# Service Configuration
MAX_RETRIES=3
RETRY_DELAY=2
SERVICE_START_TIMEOUT=60
```

## Access Methods

- **USB Serial Consoles**: `/dev/usbserial-1` to `/dev/usbserial-4` (single-port devices) or `/dev/usbserial-1.0` to `/dev/usbserial-1.3` (multi-port devices)
- **Console Commands**: `console [device]` and `list-consoles` (generated from templates)
- **Web Interface**: `http://192.168.44.1/` with upload functionality
- **TFTP**: `tftp://192.168.44.1/` for firmware transfers
- **SMB/CIFS**: `\\192.168.44.1\shared` with pi/raspberry credentials

## Template System

The project uses a sophisticated template system for maintainability:

### **Template Processing**
- Templates use `{{VARIABLE}}` syntax for substitution
- Common function: `process_template template_file output_file VAR1 value1 VAR2 value2`
- Variables sourced from `config/global.conf` with environment override support
- Atomic file replacement for reliability

### **Template Locations**
```bash
modules/*/templates/        # Module-specific templates
├── systemd service files   # Generated with proper paths and timeouts
├── configuration files     # Network, service configs with variables
├── scripts                 # Console access, startup scripts
└── documentation          # README files, access instructions
```

### **Example Template Usage**
```bash
# In template file
ExecStart={{SCRIPT_DIR}}/usbserial-startup
TimeoutStartSec={{SERVICE_START_TIMEOUT}}

# Generated output
ExecStart=/usr/local/bin/usbserial-startup
TimeoutStartSec=60
```

## Module Dependencies & Error Handling

### **Dependency Resolution**
- `network` → `system` (IP forwarding, nftables setup)
- `hostapd` → `system`, `network` (WiFi AP with routing)
- `dnsmasq` → `system`, `network` (DNS/DHCP with upstream)
- `nginx/tftp/samba` → `system`, `shared` (File services)
- `services` → All service modules (Coordination layer)

### **Error Handling Patterns**
Each module implements comprehensive error handling:
- **Module validation**: Template and config file existence checks
- **Cleanup functions**: Remove partial installations on failure
- **Retry mechanisms**: Network operations with exponential backoff
- **Lock management**: Prevent concurrent execution conflicts
- **Atomic operations**: Configuration file replacement with validation

## Development Guidelines

### **When Working with This Codebase**
1. **Configuration Changes**: Modify `config/global.conf`, not individual scripts
2. **Template Editing**: Update template files, not generated configs
3. **New Features**: Add variables to global config, use in templates
4. **Error Handling**: Follow existing patterns with validation and cleanup
5. **Testing**: Use modular installation to test individual components

### **Key Architectural Principles**
- **Separation of Concerns**: Configuration, templates, and logic are separate
- **Idempotent Operations**: Scripts can be run multiple times safely
- **Fail-Fast**: Comprehensive validation before making changes
- **Clean Rollback**: Automatic cleanup on errors
- **Template-Driven**: No hardcoded values in scripts
