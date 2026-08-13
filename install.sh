#!/bin/bash
# ==============================================================================
# osu! Linux Installer (Stable)
# Version: v5.1.1
# Author:  Kitty-Hivens
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Validate all modules are present before sourcing
REQUIRED_MODULES=(00_logger 01_cli_gui 02_deps 03_wine_env 04_osu_core 05_maintenance 06_container)
for module in "${REQUIRED_MODULES[@]}"; do
    if [ ! -f "$MODULES_DIR/${module}.sh" ]; then
        echo "Error: Missing module: ${module}.sh (expected at $MODULES_DIR/${module}.sh)"
        exit 1
    fi
    source "$MODULES_DIR/${module}.sh"
done

log_info "Starting osu! Linux Installer v5.1.1"

# --- Pre-scan for --silent so maintenance commands honor it ---
for arg in "$@"; do
    case "$arg" in
        -s|--silent) SILENT_MODE=true ;;
    esac
done

# --- Mode Dispatch ---
# Check for special modes before running the full GUI.
# Walk args by index so --import-config can grab the next positional reliably.
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
    case "${ARGS[$i]}" in
        -h|--help)       show_help ;;  # before any container prompt can get in the way
        --uninstall)     run_uninstall;    exit 0 ;;
        --health-check)  run_health_check; exit $? ;;
        --export-config) export_config;    exit 0 ;;
        --launch)        launch_osu ;;  # exec replaces the shell
        --import-config)
            i=$((i + 1))
            import_config "${ARGS[$i]:-}"
            exit 0
            ;;
    esac
    i=$((i + 1))
done

# --- Standard Installation Flow ---

# 0. Container mode. On ostree-based hosts (Bazzite, Silverblue, SteamOS) Wine cannot be
# installed into the running system without root and a reboot, so the whole installation
# runs inside a distrobox container instead. $HOME is shared, so everything the installer
# writes still lands on the host. A previous container install is remembered in the config,
# which is what lets a later plain --update find its way back inside.
container_prescan "$@"
if [ "$DISTROBOX_MODE" = false ] && ! container_active; then
    container_offer_fallback
fi
if [ "$DISTROBOX_MODE" = true ] && ! container_active; then
    # Checked here, on the host: an impossible location must cost nothing, not an image
    # pull and a full dependency bootstrap before it is noticed from the inside.
    container_validate_paths

    # The precheck further down runs inside the container and is therefore never reached on
    # this path. Building a container pulls an image and a few hundred packages, so an
    # offline host should hear about it here, not after minutes of failing downloads.
    if ! network_available; then
        if container_exists "$DISTROBOX_NAME"; then
            notify_warning "No network connection.\nContinuing with the existing container, but anything that downloads will fail."
        else
            notify_error "No network connection, and the container still has to be built.
That means downloading a container image and its packages, which cannot happen offline."
        fi
    fi

    if run_in_distrobox "$SCRIPT_DIR/install.sh" "$@"; then RC=0; else RC=$?; fi
    # KDE keeps its .desktop entries in ksycoca, which only the host can rebuild.
    refresh_desktop_caches
    exit $RC
fi

# 1. Parse CLI args or launch GUI
init_config "$@"

if [ "$DISTROBOX_MODE" = true ]; then
    container_validate_paths
fi

# Network precheck. Every remaining step fetches something -- system packages, MS .NET
# 4.8 through winetricks, the osu! client itself, fonts, the RPC bridge, icons -- so there
# is no offline path to a fresh installation. Saying so now beats failing eight minutes into
# the .NET step. A prefix that already carries osu! is only warned about: re-applying
# settings offline is legitimate, individual downloads just get skipped.
if ! network_available; then
    # An installation that already exists is anything but a bare machine: the client, or the
    # bootstrapper waiting for its first launch, or at the very least a built prefix. Only a
    # genuinely fresh install has no offline path at all.
    if [ -f "$(osu_expected_exe)" ] || [ -f "$WINE_PREFIX/osu!install.exe" ] || [ -d "$WINE_PREFIX/drive_c" ]; then
        notify_warning "No network connection.
Continuing, but anything that downloads -- fonts, the Discord RPC bridge, icons -- will be skipped or fail."
    else
        notify_error "No network connection.
osu! cannot be installed offline: the client, MS .NET 4.8 and the system packages are all downloaded during setup.
Reconnect and run the installer again."
    fi
fi

# 1a. Update mode short-circuits the full install
if [ "$UPDATE_MODE" = true ]; then
    run_update
    exit 0
fi

# 2. Check and install missing system dependencies
check_and_install_dependencies

# 3. Setup Wine environment (Prefix, .NET/Mono)
setup_wine_prefix

# 4. Configure graphics stack (OpenGL/DXVK)
configure_graphics

# 5. Install CJK fonts to fix UI rendering
install_fonts

# 6. Install Discord RPC bridge (if requested)
if [ "$INSTALL_RPC_BOOL" = "TRUE" ]; then
    install_discord_rpc
fi

# 7. Put the osu! bootstrapper in place. The client unpacks itself on first launch.
prepare_osu_client

# 8. Generate config, desktop integration, and symlinks
create_system_integration
create_osu_symlinks

log_info "Installation workflow completed successfully."

if [ "$SILENT_MODE" = false ]; then
    notify_user "Installation Complete!\n\nLaunch osu! from your application menu.\nThe first launch unpacks the client and downloads the game -- give it a few minutes.\n\nData shortcuts are available at: $LINKS_DIR\nTweak settings at: ~/.config/osu-importer/osu-env.conf"
else
    echo -e "\n[SUCCESS] osu! installation complete! Find it in your app menu."
    echo "First launch:  unpacks the client and downloads the game -- give it a few minutes."
    echo "Symlinks:  $LINKS_DIR"
    echo "Config:    ~/.config/osu-importer/osu-env.conf"
fi

ICON_NOTE=$(icon_status_note)
if [ -n "$ICON_NOTE" ]; then
    notify_warning "$ICON_NOTE"
fi

exit 0
