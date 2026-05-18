#!/bin/bash
# Module: System Dependencies

check_and_install_dependencies() {
    log_info "Checking system dependencies..."
    local NEEDS_INSTALL=""
    local NEEDS_DRIVER_INSTALL=""  # FIX: separate tracking for GPU drivers
    local DRIVERS_INSTALLED=false

    # Base dependencies (these do NOT trigger a reboot warning)
    for pkg in curl unzip winetricks; do
        if ! command -v $pkg &> /dev/null; then NEEDS_INSTALL="$NEEDS_INSTALL $pkg"; fi
    done

    # xdotool is used by the import wrapper to wait for the osu! window
    # (instead of just the process) before forwarding file paths. Soft dep:
    # Wayland-only users can skip it.
    if ! command -v xdotool &> /dev/null && ! command -v wmctrl &> /dev/null; then
        NEEDS_INSTALL="$NEEDS_INSTALL xdotool"
    fi

    # Check for ALSA plugins if ALSA is selected
    if [[ "$AUDIO_SELECTION" == *"ALSA"* ]]; then
        if ! command -v aplay &> /dev/null; then NEEDS_INSTALL="$NEEDS_INSTALL alsa-utils"; fi
    fi

    # Wine check (not a GPU driver, goes into base list)
    if ! command -v "$WINE_SELECTION" &> /dev/null && [[ "$WINE_SELECTION" != /* ]]; then
        NEEDS_INSTALL="$NEEDS_INSTALL $WINE_SELECTION"
    fi

    # Void Linux Specifics
    if command -v xbps-install &> /dev/null; then
        if ! xbps-query -l | grep -q "wine-32bit";    then NEEDS_INSTALL="$NEEDS_INSTALL wine-32bit"; fi
        if ! xbps-query -l | grep -q "libglvnd-32bit"; then NEEDS_INSTALL="$NEEDS_INSTALL libglvnd-32bit"; fi

        # FIX: GPU-specific packages go into NEEDS_DRIVER_INSTALL, not NEEDS_INSTALL
        if command -v nvidia-smi &> /dev/null || (lspci 2>/dev/null | grep -qi "nvidia"); then
            if ! xbps-query -l | grep -q "nvidia-libs-32bit"; then
                NEEDS_DRIVER_INSTALL="$NEEDS_DRIVER_INSTALL nvidia-libs-32bit"
            fi
        else
            if ! xbps-query -l | grep -q "mesa-dri-32bit"; then
                NEEDS_DRIVER_INSTALL="$NEEDS_DRIVER_INSTALL mesa-dri-32bit"
            fi
        fi

        for lib in pango-32bit cairo-32bit libXft-32bit freetype-32bit fontconfig-32bit libxml2-32bit harfbuzz-32bit; do
            if ! xbps-query -l | grep -q "$lib"; then NEEDS_INSTALL="$NEEDS_INSTALL $lib"; fi
        done
    fi

    # Install base packages (no reboot needed)
    if [ -n "$NEEDS_INSTALL" ]; then
        log_info "Installing base packages:$NEEDS_INSTALL"
        if [ "$SILENT_MODE" = false ]; then
            notify_user "Installing dependencies:\n$NEEDS_INSTALL"
        fi
        _run_package_manager $NEEDS_INSTALL
    fi

    # Install GPU drivers (reboot needed after)
    if [ -n "$NEEDS_DRIVER_INSTALL" ]; then
        log_info "Installing GPU driver packages:$NEEDS_DRIVER_INSTALL"
        if [ "$SILENT_MODE" = false ]; then
            notify_user "Installing GPU drivers:\n$NEEDS_DRIVER_INSTALL"
        fi
        _run_package_manager $NEEDS_DRIVER_INSTALL
        DRIVERS_INSTALLED=true
    fi

    # Re-evaluate WINE_BIN after potential installation
    WINE_BIN=$(command -v "$WINE_SELECTION" 2>/dev/null || echo "$WINE_SELECTION")
    export WINE="$WINE_BIN"

    if [ "$DRIVERS_INSTALLED" = true ]; then
        notify_warning "System GPU drivers were updated.\nPlease reboot your computer and run the script again."
        exit 0
    fi
}

# Internal helper: run the correct package manager
_run_package_manager() {
    local PACKAGES="$@"
    if command -v pacman &> /dev/null; then
        pkexec pacman -S $PACKAGES --noconfirm
    elif command -v apt &> /dev/null; then
        pkexec apt install -y $PACKAGES
    elif command -v dnf &> /dev/null; then
        pkexec dnf install -y $PACKAGES
    elif command -v xbps-install &> /dev/null; then
        # Enable required repos for Void
        if [[ "$PACKAGES" == *"nvidia"* ]] && ! xbps-query -L | grep -q "nonfree"; then
            pkexec xbps-install -Sy void-repo-nonfree
        fi
        if ! xbps-query -L | grep -q "multilib"; then
            pkexec xbps-install -Sy void-repo-multilib
        fi
        pkexec xbps-install -Sy $PACKAGES
    else
        log_warn "No supported package manager found. Please install manually: $PACKAGES"
    fi
}
