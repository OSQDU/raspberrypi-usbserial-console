#!/bin/bash
# lib/modules.sh - Module management for USB Serial Console installation

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Module registry
declare -A MODULES=(
    ["system"]="System preparation and validation"
    ["network"]="Network interface configuration"
    ["hostapd"]="WiFi Access Point setup"
    ["dnsmasq"]="DNS and DHCP server"
    ["nginx"]="HTTP file server"
    ["tftp"]="TFTP file server"
    ["samba"]="SMB/CIFS file sharing"
    ["udev"]="USB serial device rules"
    ["minicom"]="Serial console configuration"
    ["services"]="Systemd service coordination"
    ["shared"]="Unified file sharing setup"
)

# Module dependencies
declare -A MODULE_DEPS=(
    ["hostapd"]="system network"
    ["dnsmasq"]="system network"
    ["nginx"]="system shared"
    ["tftp"]="system shared"
    ["samba"]="system shared"
    ["udev"]="system"
    ["minicom"]="system udev"
    ["services"]="system hostapd dnsmasq"
    ["shared"]="system"
)

# Module packages
declare -A MODULE_PACKAGES=(
    ["hostapd"]="hostapd"
    ["dnsmasq"]="dnsmasq"
    ["nginx"]="nginx-light"
    ["tftp"]="tftpd-hpa"
    ["samba"]="samba samba-common-bin"
    ["minicom"]="minicom"
)

# Get module list
list_modules() {
    local available_only="${1:-false}"

    log_info "Available modules:"
    for module in "${!MODULES[@]}"; do
        local status=""
        if [[ "$available_only" == "false" ]]; then
            if is_module_installed "$module"; then
                status=" ${GREEN}[installed]${NC}"
            else
                status=" ${YELLOW}[available]${NC}"
            fi
        fi
        echo -e "  ${BLUE}$module${NC} - ${MODULES[$module]}$status"
    done
}

# Check if module exists
module_exists() {
    local module="$1"
    [[ -n "${MODULES[$module]}" ]]
}

# Check if module is installed
is_module_installed() {
    local module="$1"
    local module_file="modules/${module}/install.sh"
    local marker_file="$CONFIG_DIR/installed/$module"

    [[ -f "$marker_file" ]] && [[ -f "$module_file" ]]
}

# Get module dependencies
get_dependencies() {
    local module="$1"
    echo "${MODULE_DEPS[$module]:-}"
}

# Resolve dependency order
resolve_dependencies() {
    local -a requested_modules=("$@")
    local -a resolved=()
    local -a processing=()

    resolve_module() {
        local module="$1"

        # Check for circular dependency
        for proc in "${processing[@]}"; do
            [[ "$proc" == "$module" ]] && error_exit "Circular dependency detected: $module"
        done

        # Skip if already resolved
        for res in "${resolved[@]}"; do
            [[ "$res" == "$module" ]] && return
        done

        processing+=("$module")

        # Resolve dependencies first
        local deps
        deps=$(get_dependencies "$module")
        for dep in $deps; do
            resolve_module "$dep"
        done

        resolved+=("$module")

        # Remove from processing
        local -a new_processing=()
        for proc in "${processing[@]}"; do
            [[ "$proc" != "$module" ]] && new_processing+=("$proc")
        done
        processing=("${new_processing[@]}")
    }

    # Resolve all requested modules
    for module in "${requested_modules[@]}"; do
        module_exists "$module" || error_exit "Unknown module: $module"
        resolve_module "$module"
    done

    echo "${resolved[@]}"
}

# Install module packages
install_module_packages() {
    local module="$1"
    local packages="${MODULE_PACKAGES[$module]:-}"

    if [[ -n "$packages" ]]; then
        log_info "Installing packages for module: $module"
        for package in $packages; do
            install_package "$package"
        done
    fi
}

# Run module installation
install_module() {
    local module="$1"
    local force="${2:-false}"

    if ! module_exists "$module"; then
        error_exit "Unknown module: $module"
    fi

    if is_module_installed "$module" && [[ "$force" != "true" ]]; then
        log_info "Module already installed: $module"
        return
    fi

    local module_dir="modules/$module"
    local install_script="$module_dir/install.sh"

    if [[ ! -f "$install_script" ]]; then
        error_exit "Module installation script not found: $install_script"
    fi

    log_info "Installing module: $module"

    # Install required packages
    install_module_packages "$module"

    # Run module installation script
    (
        cd "$module_dir"
        bash install.sh
    ) || error_exit "Failed to install module: $module"

    # Mark as installed
    mkdir -p "$CONFIG_DIR/installed"
    touch "$CONFIG_DIR/installed/$module"

    log_success "Module installed: $module"
}

# Uninstall module
uninstall_module() {
    local module="$1"

    if ! is_module_installed "$module"; then
        log_warn "Module not installed: $module"
        return
    fi

    local module_dir="modules/$module"
    local uninstall_script="$module_dir/uninstall.sh"

    log_info "Uninstalling module: $module"

    # Run module uninstall script if it exists
    if [[ -f "$uninstall_script" ]]; then
        (
            cd "$module_dir"
            bash uninstall.sh
        ) || log_warn "Module uninstall script failed: $module"
    fi

    # Remove installation marker
    rm -f "$CONFIG_DIR/installed/$module"

    log_success "Module uninstalled: $module"
}

# Install multiple modules with dependency resolution
install_modules() {
    local -a modules=("$@")

    if [[ ${#modules[@]} -eq 0 ]]; then
        log_error "No modules specified"
        return 1
    fi

    # Resolve dependencies
    local -a resolved_modules
    read -ra resolved_modules <<< "$(resolve_dependencies "${modules[@]}")"

    log_info "Installation order: ${resolved_modules[*]}"

    # Install modules in order
    local total=${#resolved_modules[@]}
    local current=0

    for module in "${resolved_modules[@]}"; do
        current=$((current + 1))
        show_progress "$current" "$total" "Installing $module..."
        log_debug "About to install module: $module"
        install_module "$module" || {
            log_error "Installation failed for module: $module"
            return 1
        }
        log_debug "Successfully installed module: $module"
    done

    echo
    log_success "All modules installed successfully"
}

# Validate module installation
validate_module() {
    local module="$1"
    local module_dir="modules/$module"
    local validate_script="$module_dir/validate.sh"

    if [[ -f "$validate_script" ]]; then
        log_info "Validating module: $module"
        (
            cd "$module_dir"
            bash validate.sh
        ) || error_exit "Module validation failed: $module"
        log_success "Module validation passed: $module"
    else
        log_debug "No validation script for module: $module"
    fi
}

# Show module status
show_module_status() {
    local module="$1"

    echo "Module: $module"
    echo "Description: ${MODULES[$module]}"
    echo "Dependencies: $(get_dependencies "$module")"
    echo "Packages: ${MODULE_PACKAGES[$module]:-"none"}"

    if is_module_installed "$module"; then
        echo -e "Status: ${GREEN}installed${NC}"

        # Show service status if applicable
        case "$module" in
            hostapd|dnsmasq|nginx|tftp|samba)
                local service_status
                if systemctl is-active --quiet "$module"; then
                    service_status="${GREEN}running${NC}"
                else
                    service_status="${RED}stopped${NC}"
                fi
                echo -e "Service: $service_status"
                ;;
        esac
    else
        echo -e "Status: ${YELLOW}not installed${NC}"
    fi
}

# Module configuration
configure_module() {
    local module="$1"
    local module_dir="modules/$module"
    local config_script="$module_dir/configure.sh"

    if [[ -f "$config_script" ]]; then
        log_info "Configuring module: $module"
        (
            cd "$module_dir"
            bash configure.sh
        ) || error_exit "Module configuration failed: $module"
        log_success "Module configured: $module"
    else
        log_debug "No configuration script for module: $module"
    fi
}

# Export functions
export -f list_modules module_exists is_module_installed get_dependencies
export -f resolve_dependencies install_module uninstall_module install_modules
export -f validate_module show_module_status configure_module
