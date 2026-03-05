#!/bin/bash
# ==============================================================================
# osu! Linux Installer (Stable)
# Version: v4.2.0
# Author:  Kitty-Hivens
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Validate all modules are present before sourcing
REQUIRED_MODULES=(00_logger 01_cli_gui 02_deps 03_wine_env 04_osu_core 05_maintenance)
for module in "${REQUIRED_MODULES[@]}"; do
    if [ ! -f "$MODULES_DIR/${module}.sh" ]; then
        echo "Error: Missing module: ${module}.sh (expected at $MODULES_DIR/${module}.sh)"
        exit 1
    fi
    source "$MODULES_DIR/${module}.sh"
done

log_info "Starting osu! Linux Installer v4.2.0"

# --- Mode Dispatch ---
# Check for special modes before running the full GUI
for arg in "$@"; do
    case "$arg" in
        --uninstall)
            run_uninstall
            exit 0
            ;;
        --health-check)
            run_health_check
            exit 0
            ;;
        --export-config)
            export_config
            exit 0
            ;;
        --import-config)
            # Next arg is the file path
            shift
            import_config "$1"
            exit 0
            ;;
        --launch)
            launch_osu
            exit 0
            ;;
    esac
done

# --- Standard Installation Flow ---

# 1. Parse CLI args or launch GUI
init_config "$@"

# 2. Check and install missing system dependencies
check_and_install_dependencies

# 3. Setup Wine environment (Prefix, .NET/Mono)
setup_wine_prefix

# 4. Configure graphics stack (OpenGL/DXVK)
configure_graphics

# 5. Install CJK fonts to fix UI rendering
install_fonts

# 6. Install Discord RPC bridge (if requested)
if [ "$INSTALL_RPC_BOOL" = "TRUE" ] || [ "$INSTALL_RPC_BOOL" = "true" ]; then
    install_discord_rpc
fi

# 7. Download and perform initial osu! setup
install_osu_client

# 8. Generate config, desktop integration, and symlinks
create_system_integration
create_osu_symlinks

log_info "Installation workflow completed successfully."

if [ "$SILENT_MODE" = false ]; then
    notify_user "Installation Complete!\n\nLaunch osu! from your application menu.\n\nData shortcuts are available at: $LINKS_DIR\nTweak settings at: ~/.config/osu-importer/osu-env.conf"
else
    echo -e "\n[SUCCESS] osu! installation complete! Find it in your app menu."
    echo "Symlinks:  $LINKS_DIR"
    echo "Config:    ~/.config/osu-importer/osu-env.conf"
fi

exit 0
