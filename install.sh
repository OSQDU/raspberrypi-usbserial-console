#!/bin/bash
# install.sh - Main installation script for USB Serial Console

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Source libraries
# source "lib/common.sh", this will be sourced by lib/modules.sh
source "lib/modules.sh"

# Default modules for full installation
readonly DEFAULT_MODULES=(
    "system"
    "network"
    "shared"
    "udev"
    "hostapd"
    "dnsmasq"
    "nginx"
    "tftp"
    "samba"
    "minicom"
    "services"
)

show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                      USB Serial Console                      ║
║                         Installation                         ║
║                                                              ║
║  Modern, modular Raspberry Pi network management appliance   ║
║  with USB serial console access and file sharing.            ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [MODULES...]

Options:
    -h, --help              Show this help message
    -l, --list              List available modules
    -a, --all               Install all modules (default)
    -v, --verbose           Enable verbose output
    -f, --force             Force reinstallation of modules
    -s, --status            Show module status
    -c, --configure         Configure modules after installation
    -u, --uninstall MODULE  Uninstall specific module
    --validate MODULE       Validate module installation
    --dry-run              Show what would be done without executing

Modules:
$(list_modules true | sed 's/^/    /')

Examples:
    $0                      # Install all modules
    $0 system shared udev   # Install specific modules
    $0 --list               # Show available modules
    $0 --status             # Show installation status
    $0 --uninstall samba    # Remove samba module

For more information, see README.md
EOF
}

validate_environment() {
    log_info "Validating environment..."

    # Check if running on Raspberry Pi
    if [[ ! -f "/proc/device-tree/model" ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        log_warn "This script is designed for Raspberry Pi hardware"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        [[ ${REPLY} =~ ^[Yy]$ ]] || exit 1
    fi

    # Check operating system
    if [[ ! -f "/etc/os-release" ]] || ! grep -q -E "Raspbian|Raspberry Pi OS" /etc/os-release; then
        log_warn "This script is designed for Raspberry Pi OS"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        [[ ${REPLY} =~ ^[Yy]$ ]] || exit 1
    fi

    # Check WiFi capability
    if [[ -z "$(get_wifi_interface)" ]]; then
        error_exit "No WiFi interface detected. This project requires WiFi capability."
    fi

    log_success "Environment validation passed"
}

main() {
    local -a modules_to_install=()
    local install_all=true
    local force=false
    local show_status=false
    local configure_only=false
    local dry_run=false
    local module_to_uninstall=""
    local module_to_validate=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_modules
                exit 0
                ;;
            -a|--all)
                install_all=true
                shift
                ;;
            -v|--verbose)
                export DEBUG=1
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -s|--status)
                show_status=true
                shift
                ;;
            -c|--configure)
                configure_only=true
                shift
                ;;
            -u|--uninstall)
                module_to_uninstall="$2"
                shift 2
                ;;
            --validate)
                module_to_validate="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                modules_to_install+=("$1")
                install_all=false
                shift
                ;;
        esac
    done

    # Check for root privileges
    require_root

    # Show banner
    show_banner

    # Handle special actions
    if [[ -n "${module_to_uninstall}" ]]; then
        uninstall_module "${module_to_uninstall}"
        exit 0
    fi

    if [[ -n "${module_to_validate}" ]]; then
        validate_module "${module_to_validate}"
        exit 0
    fi

    if [[ "${show_status}" == "true" ]]; then
        log_info "Module installation status:"
        for module in "${DEFAULT_MODULES[@]}"; do
            show_module_status "${module}"
            echo
        done
        exit 0
    fi

    # Validate environment
    validate_environment

    # Determine modules to install
    if [[ "${install_all}" == "true" ]]; then
        modules_to_install=("${DEFAULT_MODULES[@]}")
    fi

    if [[ ${#modules_to_install[@]} -eq 0 ]]; then
        error_exit "No modules specified. Use --help for usage information."
    fi

    # Show what will be installed
    log_info "Pi Model: $(detect_pi_model)"
    log_info "WiFi Interface: $(get_wifi_interface)"
    log_info "Installation mode: ${force:+force }install"

    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN - Would install modules: ${modules_to_install[*]}"
        local -a resolved
        read -ra resolved <<< "$(resolve_dependencies "${modules_to_install[@]}")"
        log_info "DRY RUN - Resolved installation order: ${resolved[*]}"
        exit 0
    fi

    # Install modules
    if [[ "${configure_only}" != "true" ]]; then
        install_modules "${modules_to_install[@]}"
    fi

    # Configure modules
    if [[ "${configure_only}" == "true" ]] || [[ "${force}" == "true" ]]; then
        log_info "Configuring modules..."
        for module in "${modules_to_install[@]}"; do
            configure_module "${module}"
        done
    fi

    # Handle deferred NetworkManager restart
    if [[ "${RESTART_NETWORKMANAGER_LATER:-false}" == "true" ]]; then
        log_info "Restarting NetworkManager to apply configuration changes..."
        if systemctl restart NetworkManager 2>/dev/null; then
            log_success "NetworkManager restarted successfully"
        else
            log_warn "Failed to restart NetworkManager - you may need to restart manually"
        fi
        echo
    fi

    # Final summary
    log_success "Installation completed successfully!"
    echo
    log_info "Next steps:"
    if [[ "${RESTART_NETWORKMANAGER_LATER:-false}" == "true" ]]; then
        log_info "1. NetworkManager has been restarted (WiFi may have disconnected)"
        log_info "2. Reboot the system: sudo reboot"
        log_info "3. Connect to WiFi: USBSerial-Console"
        log_info "4. Access web interface: http://192.168.44.1/"
        log_info "5. Connect USB serial devices and access via /dev/usbserial-X[.Y]"
    else
        log_info "1. Reboot the system: sudo reboot"
        log_info "2. Connect to WiFi: USBSerial-Console"
        log_info "3. Access web interface: http://192.168.44.1/"
        log_info "4. Connect USB serial devices and access via /dev/usbserial-X[.Y]"
    fi
    echo
    log_info "For troubleshooting, check logs in: ${LOG_DIR}"
}

main "$@"
