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

    # icoutils ships wrestool/icotool, which pull the launcher icon straight out of
    # osu!.exe. The binary name does not match the package name, so check it separately.
    if ! command -v wrestool &> /dev/null; then NEEDS_INSTALL="$NEEDS_INSTALL icoutils"; fi

    # Check for ALSA plugins if ALSA is selected
    if [[ "$AUDIO_SELECTION" == *"ALSA"* ]]; then
        if ! command -v aplay &> /dev/null; then NEEDS_INSTALL="$NEEDS_INSTALL alsa-utils"; fi
    fi

    # Wine: the binary is always `wine`; the SELECTION names which package to install.
    # If `wine` is already present, install nothing (covers wine-staging providing it).
    if [[ "$WINE_SELECTION" != /* ]] && ! command -v wine &> /dev/null; then
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
    WINE_BIN=$(resolve_wine_bin "$WINE_SELECTION")
    export WINE="$WINE_BIN"

    if [ "$DRIVERS_INSTALLED" = true ]; then
        notify_warning "System GPU drivers were updated.\nPlease reboot your computer and run the script again."
        exit 0
    fi
}

# Internal helper: run the correct package manager
_run_package_manager() {
    local PACKAGES="$@"

    # An ostree system layers packages into the next boot's image, not the running one, so
    # a normal install here would either fail or need a reboot to mean anything.
    if host_is_immutable && ! container_active; then
        log_warn "This system installs packages through an image (ostree) and cannot add them on the fly."
        log_warn "Missing:$PACKAGES"
        log_warn "Re-run with --distrobox to install everything into a container instead."
        return 0
    fi

    # Inside the container there is no polkit agent to answer pkexec, but distrobox
    # grants the user passwordless sudo.
    local ELEVATE="pkexec"
    container_active && ELEVATE="sudo"

    if command -v pacman &> /dev/null; then
        $ELEVATE pacman -S $PACKAGES --noconfirm
    elif command -v apt &> /dev/null; then
        $ELEVATE apt install -y $PACKAGES
    elif command -v dnf &> /dev/null; then
        $ELEVATE dnf install -y $PACKAGES
    elif command -v xbps-install &> /dev/null; then
        # Enable required repos for Void
        if [[ "$PACKAGES" == *"nvidia"* ]] && ! xbps-query -L | grep -q "nonfree"; then
            $ELEVATE xbps-install -Sy void-repo-nonfree
        fi
        if ! xbps-query -L | grep -q "multilib"; then
            $ELEVATE xbps-install -Sy void-repo-multilib
        fi
        $ELEVATE xbps-install -Sy $PACKAGES
    elif [ -f /etc/NIXOS ] || grep -qi nixos /etc/os-release 2>/dev/null; then
        log_warn "NixOS detected, and these deps aren't on PATH: $PACKAGES"
        log_warn "Run the installer through the flake so Nix provides them:"
        log_warn "    nix develop   # then: ./install.sh"
        log_warn "    nix run github:Kitty-Hivens/linux-osu-stable-installer   # one-shot"
    else
        log_warn "No supported package manager found. Please install manually: $PACKAGES"
        log_warn "Alternatively, re-run with --distrobox to install everything into a container."
    fi
}
