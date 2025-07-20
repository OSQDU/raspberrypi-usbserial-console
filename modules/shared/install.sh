#!/bin/bash
# modules/shared/install.sh - Unified file sharing setup

source "../../lib/common.sh"

main() {
    log_info "Installing shared file directory module..."
    
    # Run the shared directory setup script
    bash "shared-directory-setup.sh"
    
    log_success "Shared module installed successfully"
}

main "$@"
