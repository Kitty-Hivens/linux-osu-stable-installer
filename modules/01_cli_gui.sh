#!/bin/bash
# Module: CLI Parser and YAD GUI Dashboard

# Global Configuration Variables (Defaults)
DEFAULT_PREFIX="$HOME/.wine-osu"
if [ -d "$HOME/.osu-wine" ]; then DEFAULT_PREFIX="$HOME/.osu-wine"; fi

BEST_WINE="wine"
if command -v wine-staging &> /dev/null; then BEST_WINE="wine-staging"; fi

WINE_PREFIX="$DEFAULT_PREFIX"
WINE_SELECTION="$BEST_WINE"
RENDERER_SELECTION="OpenGL (Stable)"
DRIVER_SELECTION="X11 (Recommended)"
FONT_SELECTION="Noto Sans CJK"
INSTALL_RPC_BOOL="TRUE"
DOTNET_SELECTION="MS .NET 4.8 (Recommended)"
AUDIO_SELECTION="PulseAudio/PipeWire"
ENABLE_FSYNC="TRUE"
ENABLE_GAMEMODE="TRUE"
SILENT_MODE=false
UPDATE_MODE=false
LINKS_DIR="$HOME/osu"

show_help() {
    cat << EOF
Usage: ./install.sh [OPTIONS]

Installation Options:
  -p, --prefix DIR       Wine prefix directory (default: $DEFAULT_PREFIX)
  -w, --wine BIN         Wine binary or path (default: $BEST_WINE)
  -a, --api API          Graphics API: 'opengl' or 'dxvk' (default: opengl)
  -d, --driver DRIVER    Window driver: 'x11' or 'wayland' (default: x11)
  -f, --font FONT        Fonts: 'wqy', 'noto', 'koruri', 'system', 'skip' (default: noto)
      --rpc true/false   Install Discord RPC Bridge (default: true)
      --dotnet TYPE      Runtime: 'net48' or 'mono' (default: net48)
      --audio TYPE       Audio backend: 'pulse' or 'alsa' (default: pulse)
      --no-sync          Disable WINEFSYNC/WINEESYNC/WINENTSYNC
      --no-gamemode      Disable Feral GameMode integration
      --links-dir DIR    Symlink directory for Songs/Skins/Logs/Chat (default: ~/osu)

Maintenance:
      --update           Re-apply settings over existing installation
      --uninstall        Remove osu! and all integration files
      --health-check     Verify installation integrity
      --export-config    Export current config to osu-config-backup.tar.gz
      --import-config F  Import config from a backup file
      --launch           Launch osu! using the current configuration

General:
  -s, --silent           Unattended CLI mode (no YAD GUI)
  -h, --help             Show this help message
EOF
    exit 0
}

parse_cli() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--prefix) WINE_PREFIX="$2"; shift ;;
            -w|--wine) WINE_SELECTION="$2"; shift ;;
            -a|--api)
                if [[ "$2" == "dxvk" ]]; then RENDERER_SELECTION="DXVK (Low Latency)"
                else RENDERER_SELECTION="OpenGL (Stable)"; fi
                shift ;;
            -d|--driver)
                if [[ "$2" == "wayland" ]]; then DRIVER_SELECTION="Wayland (Native)"
                else DRIVER_SELECTION="X11 (Recommended)"; fi
                shift ;;
            -f|--font)
                case "$2" in
                    wqy)    FONT_SELECTION="WenQuanYi (Micro Hei)" ;;
                    koruri) FONT_SELECTION="Koruri" ;;
                    system) FONT_SELECTION="System Links" ;;
                    skip)   FONT_SELECTION="Skip" ;;
                    *)      FONT_SELECTION="Noto Sans CJK" ;;
                esac
                shift ;;
            --rpc)
                if [[ "$2" == "false" ]]; then INSTALL_RPC_BOOL="FALSE"
                else INSTALL_RPC_BOOL="TRUE"; fi
                shift ;;
            --dotnet)
                if [[ "$2" == "mono" ]]; then DOTNET_SELECTION="Wine Mono (Experimental)"
                else DOTNET_SELECTION="MS .NET 4.8 (Recommended)"; fi
                shift ;;
            --audio)
                if [[ "$2" == "alsa" ]]; then AUDIO_SELECTION="ALSA (Lowest Latency)"
                else AUDIO_SELECTION="PulseAudio/PipeWire"; fi
                shift ;;
            --links-dir) LINKS_DIR="$2"; shift ;;
            --no-sync)      ENABLE_FSYNC="FALSE" ;;
            --no-gamemode)  ENABLE_GAMEMODE="FALSE" ;;
            --update)       UPDATE_MODE=true ;;
            # Maintenance modes are handled in install.sh before init_config,
            # but we consume them here to avoid "unknown parameter" warnings.
            --uninstall|--health-check|--export-config|--import-config|--launch) ;;
            -s|--silent) SILENT_MODE=true ;;
            -h|--help) show_help ;;
            *) log_warn "Unknown parameter: $1"; show_help ;;
        esac
        shift
    done
}

run_gui() {
    log_info "Launching YAD Dashboard..."
    local VALUES

    VALUES=$(yad --form --center --width=750 --columns=2 \
        --title="$SCRIPT_TITLE" \
        --window-icon="$ICON" --image="$ICON" \
        --text="<b>osu! Configuration Dashboard</b> v4.2.0\nFine-tune your installation parameters:" \
        --field="Install Location:DIR"        "$WINE_PREFIX" \
        --field="Wine Binary:CB"              "$BEST_WINE!Custom Path" \
        --field="Graphics API:CB"             "OpenGL (Stable)!DXVK (Low Latency)" \
        --field="Window Driver:CB"            "X11 (Recommended)!Wayland (Native)" \
        --field="Fonts:CB"                    "Noto Sans CJK!WenQuanYi (Micro Hei)!Koruri!System Links!Skip" \
        --field="Discord RPC:CHK"             "$INSTALL_RPC_BOOL" \
        --field=".NET Runtime:CB"             "MS .NET 4.8 (Recommended)!Wine Mono (Experimental)" \
        --field="Audio Backend:CB"            "PulseAudio/PipeWire!ALSA (Lowest Latency)" \
        --field="Enable FSync/ESync:CHK"      "$ENABLE_FSYNC" \
        --field="Enable GameMode:CHK"         "$ENABLE_GAMEMODE" \
        --field="Symlinks Directory:DIR"      "$LINKS_DIR" \
        --separator="|")

    if [ $? -ne 0 ] || [ -z "$VALUES" ]; then
        log_info "Installation cancelled by user."
        exit 0
    fi

    IFS="|" read -r WINE_PREFIX WINE_SELECTION RENDERER_SELECTION DRIVER_SELECTION \
                    FONT_SELECTION INSTALL_RPC_BOOL DOTNET_SELECTION AUDIO_SELECTION \
                    ENABLE_FSYNC ENABLE_GAMEMODE LINKS_DIR <<< "$VALUES"

    if [ "$WINE_SELECTION" = "Custom Path" ]; then
        WINE_BIN=$(yad --file-selection --title="Select Wine Executable" --file-filter="Executable | wine")
        if [ -z "$WINE_BIN" ]; then exit 1; fi
        WINE_SELECTION="$WINE_BIN"
    fi
}

init_config() {
    parse_cli "$@"

    if [ "$SILENT_MODE" = false ]; then
        # NixOS guard
        if [ -f "/etc/NIXOS" ] || grep -q "NixOS" /etc/os-release 2>/dev/null; then
            if ! command -v yad &> /dev/null; then
                notify_error "NixOS detected. Please install 'yad' manually, or use --silent flag."
            fi
        fi

        # Auto-install YAD if missing
        if ! command -v yad &> /dev/null; then
            echo "YAD not found. Attempting to install..."
            if command -v pacman &> /dev/null;      then pkexec pacman -S yad --noconfirm
            elif command -v apt &> /dev/null;        then pkexec apt update && pkexec apt install -y yad
            elif command -v dnf &> /dev/null;        then pkexec dnf install -y yad
            elif command -v xbps-install &> /dev/null; then pkexec xbps-install -S -y yad
            else notify_error "Package manager not found. Install 'yad' manually or use --silent."; fi
        fi

        run_gui
    fi

    # Resolve WINE_BIN
    if ! command -v "$WINE_SELECTION" &> /dev/null && [ ! -x "$WINE_SELECTION" ]; then
        log_warn "Wine binary '$WINE_SELECTION' not found in PATH. It may be installed by the dependency step."
    fi
    WINE_BIN=$(command -v "$WINE_SELECTION" 2>/dev/null || echo "$WINE_SELECTION")

    export WINE="$WINE_BIN"
    export WINEPREFIX="$WINE_PREFIX"

    log_info "Configuration initialized."
    log_info "  Prefix:  $WINE_PREFIX"
    log_info "  Wine:    $WINE_BIN"
    log_info "  API:     $RENDERER_SELECTION | Driver: $DRIVER_SELECTION"
    log_info "  Audio:   $AUDIO_SELECTION    | Runtime: $DOTNET_SELECTION"
    log_info "  Symlinks: $LINKS_DIR"
}
