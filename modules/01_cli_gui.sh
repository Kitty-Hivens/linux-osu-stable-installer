#!/bin/bash
# Module: CLI Parser and gum TUI Dashboard

# Global Configuration Variables (Defaults)
DEFAULT_PREFIX="$HOME/.wine-osu"
if [ -d "$HOME/.osu-wine" ]; then DEFAULT_PREFIX="$HOME/.osu-wine"; fi

BEST_WINE="wine"
if command -v wine &> /dev/null && wine --version 2>/dev/null | grep -qi staging; then
    BEST_WINE="wine-staging"
fi

WINE_PREFIX="$DEFAULT_PREFIX"
WINE_SELECTION="$BEST_WINE"
RENDERER_SELECTION="OpenGL (Stable)"
DRIVER_SELECTION="Wayland (Recommended)"
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
  -d, --driver DRIVER    Window driver: 'x11' or 'wayland' (default: wayland)
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
  -s, --silent           Unattended CLI mode (no TUI dashboard)
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
                if [[ "$2" == "x11" ]]; then DRIVER_SELECTION="X11 (Fallback)"
                else DRIVER_SELECTION="Wayland (Recommended)"; fi
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

run_tui() {
    if ! command -v gum &> /dev/null; then
        log_warn "gum not found -- skipping interactive dashboard; using defaults / CLI flags."
        return
    fi
    log_info "Launching TUI dashboard..."

    # Any cancel (Esc/Ctrl-C) on a required prompt aborts the install cleanly.
    _abort() { log_info "Installation cancelled."; exit 0; }

    gum style --border rounded --padding "1 3" --margin "1 0" --border-foreground 212 \
        "osu! Configuration Dashboard  v5.0.1" "" "Pick options, Enter confirms each." || true

    WINE_PREFIX=$(gum input --width 72 --prompt "Install location > " --value "$WINE_PREFIX") || _abort
    [ -n "$WINE_PREFIX" ] || WINE_PREFIX="$DEFAULT_PREFIX"

    local _wine _w _wines=("$BEST_WINE") _seen=" $BEST_WINE "
    for _w in wine wine-staging; do                          # package labels, not binaries
        case "$_seen" in *" $_w "*) continue ;; esac
        _wines+=("$_w"); _seen+="$_w "
    done
    _wines+=("Custom path...")
    _wine=$(gum choose --header "Wine binary" "${_wines[@]}") || _abort
    if [ "$_wine" = "Custom path..." ]; then
        WINE_SELECTION=$(gum input --width 72 --prompt "Wine path > " --placeholder "/usr/bin/wine") || _abort
    else
        WINE_SELECTION="$_wine"
    fi

    RENDERER_SELECTION=$(gum choose --header "Graphics API" "OpenGL (Stable)" "DXVK (Low Latency)") || _abort
    DRIVER_SELECTION=$(gum choose --header "Window driver" "Wayland (Recommended)" "X11 (Fallback)") || _abort
    FONT_SELECTION=$(gum choose --header "Fonts" "Noto Sans CJK" "WenQuanYi (Micro Hei)" "Koruri" "System Links" "Skip") || _abort
    DOTNET_SELECTION=$(gum choose --header ".NET runtime" "MS .NET 4.8 (Recommended)" "Wine Mono (Experimental)") || _abort
    AUDIO_SELECTION=$(gum choose --header "Audio backend" "PulseAudio/PipeWire" "ALSA (Lowest Latency)") || _abort
    LINKS_DIR=$(gum input --width 72 --prompt "Symlinks dir > " --value "$LINKS_DIR") || _abort
    [ -n "$LINKS_DIR" ] || LINKS_DIR="$HOME/osu"

    gum confirm "Install Discord RPC bridge?" && INSTALL_RPC_BOOL=TRUE || INSTALL_RPC_BOOL=FALSE
    gum confirm "Enable FSync/ESync?"         && ENABLE_FSYNC=TRUE     || ENABLE_FSYNC=FALSE
    gum confirm "Enable Feral GameMode?"      && ENABLE_GAMEMODE=TRUE  || ENABLE_GAMEMODE=FALSE

    # Everything confirmed here counts as an explicit user choice.
    USER_SET_PREFIX=true; USER_SET_WINE=true; USER_SET_RENDERER=true; USER_SET_DRIVER=true
    USER_SET_FONT=true; USER_SET_RPC=true; USER_SET_DOTNET=true; USER_SET_AUDIO=true
    USER_SET_FSYNC=true; USER_SET_GAMEMODE=true; USER_SET_LINKS=true
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
        # gum drives the TUI dashboard; run_tui falls back to defaults if gum is absent.
        [ "$UPDATE_MODE" = false ] && run_tui
    elif [ "$IS_NIXOS" = true ]; then
        log_warn "NixOS detected -- the installer won't install system packages."
        log_warn "Run it through the flake so Nix provides deps: 'nix develop' then ./install.sh, or 'nix run .'."
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

    # Resolve WINE_BIN (wine/wine-staging both map to the `wine` binary).
    WINE_BIN=$(resolve_wine_bin "$WINE_SELECTION")
    if [ ! -x "$WINE_BIN" ] && ! command -v "$WINE_BIN" &> /dev/null; then
        log_warn "Wine binary not found yet ('$WINE_BIN'); the dependency step may install it."
    fi

    export WINE="$WINE_BIN"
    export WINEPREFIX="$WINE_PREFIX"

    log_info "Configuration initialized."
    log_info "  Prefix:  $WINE_PREFIX"
    log_info "  Wine:    $WINE_BIN"
    log_info "  API:     $RENDERER_SELECTION | Driver: $DRIVER_SELECTION"
    log_info "  Audio:   $AUDIO_SELECTION    | Runtime: $DOTNET_SELECTION"
    log_info "  Symlinks: $LINKS_DIR"
}
