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
            -p|--prefix) WINE_PREFIX="$2"; USER_SET_PREFIX=true; shift ;;
            -w|--wine) WINE_SELECTION="$2"; USER_SET_WINE=true; shift ;;
            -a|--api)
                if [[ "$2" == "dxvk" ]]; then RENDERER_SELECTION="DXVK (Low Latency)"
                else RENDERER_SELECTION="OpenGL (Stable)"; fi
                USER_SET_RENDERER=true
                shift ;;
            -d|--driver)
                if [[ "$2" == "wayland" ]]; then DRIVER_SELECTION="Wayland (Native)"
                else DRIVER_SELECTION="X11 (Recommended)"; fi
                USER_SET_DRIVER=true
                shift ;;
            -f|--font)
                case "$2" in
                    wqy)    FONT_SELECTION="WenQuanYi (Micro Hei)" ;;
                    koruri) FONT_SELECTION="Koruri" ;;
                    system) FONT_SELECTION="System Links" ;;
                    skip)   FONT_SELECTION="Skip" ;;
                    *)      FONT_SELECTION="Noto Sans CJK" ;;
                esac
                USER_SET_FONT=true
                shift ;;
            --rpc)
                if [[ "$2" == "false" ]]; then INSTALL_RPC_BOOL="FALSE"
                else INSTALL_RPC_BOOL="TRUE"; fi
                USER_SET_RPC=true
                shift ;;
            --dotnet)
                if [[ "$2" == "mono" ]]; then DOTNET_SELECTION="Wine Mono (Experimental)"
                else DOTNET_SELECTION="MS .NET 4.8 (Recommended)"; fi
                USER_SET_DOTNET=true
                shift ;;
            --audio)
                if [[ "$2" == "alsa" ]]; then AUDIO_SELECTION="ALSA (Lowest Latency)"
                else AUDIO_SELECTION="PulseAudio/PipeWire"; fi
                USER_SET_AUDIO=true
                shift ;;
            --links-dir) LINKS_DIR="$2"; USER_SET_LINKS=true; shift ;;
            --no-sync)      ENABLE_FSYNC="FALSE";     USER_SET_FSYNC=true ;;
            --no-gamemode)  ENABLE_GAMEMODE="FALSE";  USER_SET_GAMEMODE=true ;;
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

    # Everything the user just confirmed in the dashboard counts as an explicit choice.
    USER_SET_PREFIX=true
    USER_SET_WINE=true
    USER_SET_RENDERER=true
    USER_SET_DRIVER=true
    USER_SET_FONT=true
    USER_SET_RPC=true
    USER_SET_DOTNET=true
    USER_SET_AUDIO=true
    USER_SET_FSYNC=true
    USER_SET_GAMEMODE=true
    USER_SET_LINKS=true
}

# Pull a single key=value line from osu-env.conf without sourcing the whole file
# (sourcing would also import Wine env vars and pollute the installer's environment).
_get_stored() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return 1
    grep -E "^[[:space:]]*${key}=" "$file" 2>/dev/null \
        | tail -n 1 \
        | sed -E "s/^[[:space:]]*${key}=//; s/^\"//; s/\"$//"
}

# Restore stored user choices for --update, leaving anything the user explicitly
# passed on the CLI alone (those have USER_SET_* set by parse_cli).
load_installer_state() {
    local STORED="$HOME/.config/osu-importer/osu-env.conf"
    if [ ! -f "$STORED" ]; then
        notify_error "No existing installation found.\nConfig not present at: $STORED\n\nRun a fresh install first."
    fi

    local _v
    [ "${USER_SET_PREFIX:-false}"   = false ] && _v=$(_get_stored "$STORED" WINE_PREFIX)                  && [ -n "$_v" ] && WINE_PREFIX="$_v"
    [ "${USER_SET_WINE:-false}"     = false ] && _v=$(_get_stored "$STORED" INSTALLER_WINE_SELECTION)     && [ -n "$_v" ] && WINE_SELECTION="$_v"
    [ "${USER_SET_RENDERER:-false}" = false ] && _v=$(_get_stored "$STORED" INSTALLER_RENDERER_SELECTION) && [ -n "$_v" ] && RENDERER_SELECTION="$_v"
    [ "${USER_SET_DRIVER:-false}"   = false ] && _v=$(_get_stored "$STORED" INSTALLER_DRIVER_SELECTION)   && [ -n "$_v" ] && DRIVER_SELECTION="$_v"
    [ "${USER_SET_FONT:-false}"     = false ] && _v=$(_get_stored "$STORED" INSTALLER_FONT_SELECTION)     && [ -n "$_v" ] && FONT_SELECTION="$_v"
    [ "${USER_SET_AUDIO:-false}"    = false ] && _v=$(_get_stored "$STORED" INSTALLER_AUDIO_SELECTION)    && [ -n "$_v" ] && AUDIO_SELECTION="$_v"
    [ "${USER_SET_DOTNET:-false}"   = false ] && _v=$(_get_stored "$STORED" INSTALLER_DOTNET_SELECTION)   && [ -n "$_v" ] && DOTNET_SELECTION="$_v"
    [ "${USER_SET_RPC:-false}"      = false ] && _v=$(_get_stored "$STORED" INSTALLER_INSTALL_RPC_BOOL)   && [ -n "$_v" ] && INSTALL_RPC_BOOL="$_v"
    [ "${USER_SET_FSYNC:-false}"    = false ] && _v=$(_get_stored "$STORED" INSTALLER_ENABLE_FSYNC)       && [ -n "$_v" ] && ENABLE_FSYNC="$_v"
    [ "${USER_SET_GAMEMODE:-false}" = false ] && _v=$(_get_stored "$STORED" INSTALLER_ENABLE_GAMEMODE)    && [ -n "$_v" ] && ENABLE_GAMEMODE="$_v"
    [ "${USER_SET_LINKS:-false}"    = false ] && _v=$(_get_stored "$STORED" INSTALLER_LINKS_DIR)          && [ -n "$_v" ] && LINKS_DIR="$_v"

    # OSU_LINUX path always comes from stored state (no CLI flag for it)
    _v=$(_get_stored "$STORED" OSU_LINUX) && [ -n "$_v" ] && TARGET_OSU_EXE="$_v"
}

init_config() {
    parse_cli "$@"

    local IS_NIXOS=false
    if [ -f "/etc/NIXOS" ] || grep -q "NixOS" /etc/os-release 2>/dev/null; then
        IS_NIXOS=true
    fi

    if [ "$SILENT_MODE" = false ]; then
        # NixOS guard — auto-install can't work, so require yad pre-installed.
        if [ "$IS_NIXOS" = true ] && ! command -v yad &> /dev/null; then
            notify_error "NixOS detected. Please install 'yad' manually, or use --silent flag."
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

        [ "$UPDATE_MODE" = false ] && run_gui
    elif [ "$IS_NIXOS" = true ]; then
        log_warn "NixOS detected — the installer cannot install system packages."
        log_warn "Ensure 'wine', 'winetricks', and 32-bit graphics libs are available in your environment."
    fi

    # In update mode, restore prior selections from osu-env.conf so re-applying
    # uses what the user actually chose last time — not parse_cli's defaults.
    # Explicit CLI flags still win (parse_cli set USER_SET_* for those).
    if [ "$UPDATE_MODE" = true ]; then
        load_installer_state
    fi

    # Normalize boolean flags so downstream code only checks one spelling.
    _normalize_bool() {
        case "${1^^}" in
            TRUE|1|YES|ON) echo "TRUE" ;;
            *) echo "FALSE" ;;
        esac
    }
    INSTALL_RPC_BOOL=$(_normalize_bool "$INSTALL_RPC_BOOL")
    ENABLE_FSYNC=$(_normalize_bool "$ENABLE_FSYNC")
    ENABLE_GAMEMODE=$(_normalize_bool "$ENABLE_GAMEMODE")

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
