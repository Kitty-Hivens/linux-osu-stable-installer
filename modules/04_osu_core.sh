#!/bin/bash
# Module: osu! Download, RPC, System Integration, and Symlinks

install_discord_rpc() {
    log_info "Setting up Discord RPC Bridge..."

    local RPC_SCRIPT=$(cat << 'EOF'
        set +e  # FIX: Disable set -e locally — Wine/wineserver commands return non-zero on "already stopped" etc.

        echo "Stopping and cleaning old bridge (if any)..."
        WINEPREFIX="$WINE_PREFIX" WAYLAND_DISPLAY="" "$WINE_BIN" net stop rpc-bridge &>/dev/null
        WINEPREFIX="$WINE_PREFIX" WAYLAND_DISPLAY="" "$WINE_BIN" taskkill /IM bridge.exe /F &>/dev/null
        rm -f "$WINE_PREFIX/drive_c/windows/bridge.exe"

        echo "Downloading RPC Bridge..."
        TEMP_DIR="$WINE_PREFIX/drive_c/windows/temp_bridge"
        mkdir -p "$TEMP_DIR"

        if ! download \
            "https://github.com/EnderIce2/rpc-bridge/releases/latest/download/bridge.zip" \
            "$TEMP_DIR/bridge.zip"; then
            echo "[ERROR] Failed to download Discord RPC Bridge. Skipping."
            rm -rf "$TEMP_DIR"
            set -e
            exit 0
        fi

        unzip -o -q "$TEMP_DIR/bridge.zip" -d "$TEMP_DIR"
        BRIDGE_EXE=$(find "$TEMP_DIR" -name "bridge.exe" | head -n 1)

        if [ -n "$BRIDGE_EXE" ]; then
            echo "Installing bridge..."
            WINEPREFIX="$WINE_PREFIX" WAYLAND_DISPLAY="" "$WINE_BIN" "$BRIDGE_EXE" --install
            echo "Discord RPC Bridge installed successfully."
        else
            echo "[ERROR] bridge.exe not found in archive. Skipping."
        fi

        rm -rf "$TEMP_DIR"
        set -e
EOF
)

    command -v gum &> /dev/null && gum style --foreground 212 "Installing Discord Rich Presence..." || true
    eval "$RPC_SCRIPT"
}

install_osu_client() {
    log_info "Checking for existing osu! installation..."

    local WINE_USER
    WINE_USER=$(ls -1 "$WINE_PREFIX/drive_c/users/" 2>/dev/null | grep -v "Public" | head -n 1)
    [ -z "$WINE_USER" ] && WINE_USER="$USER"
    local EXPECTED_PATH="$WINE_PREFIX/drive_c/users/$WINE_USER/AppData/Local/osu!/osu!.exe"

    TARGET_OSU_EXE="$EXPECTED_PATH"

    if [ ! -f "$TARGET_OSU_EXE" ]; then
        TARGET_OSU_EXE=$(find "$WINE_PREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)
    fi

    if [ -z "$TARGET_OSU_EXE" ] || [ ! -f "$TARGET_OSU_EXE" ]; then
        log_info "Downloading osu! installer..."
        if ! download "https://m1.ppy.sh/r/osu!install.exe" "$WINE_PREFIX/osu!install.exe"; then
            notify_error "Failed to download osu!install.exe from m1.ppy.sh. Check your connection and try again."
        fi

        if [ "$SILENT_MODE" = false ] && command -v gum &> /dev/null; then
            gum style --border rounded --padding "1 2" --border-foreground 214 \
                "READ CAREFULLY" "" \
                "osu! will now download its files. With Wine Mono the updater window may" \
                "crash or vanish at 100% -- DO NOT PANIC, the script catches it and relaunches" \
                "the game. Wait for the osu! main menu, then close it normally."
            gum confirm "Understood, continue?" || notify_error "Aborted at osu! download step."
        else
            echo -e "\n[ACTION REQUIRED] osu! is downloading its files."
            echo "Because of Wine Mono, the updater might crash and restart automatically."
            echo "Please wait for it to reach the main menu, then close it completely."
        fi

        log_info "Launching osu! installer..."
        env WINENTSYNC=0 WINEFSYNC=0 WINEESYNC=0 WINEWAYLAND=0 WAYLAND_DISPLAY="" \
            WINEPREFIX="$WINE_PREFIX" LC_ALL=en_US.UTF-8 \
            "$WINE_BIN" "$WINE_PREFIX/osu!install.exe" &
        local INSTALLER_PID=$!

        log_info "Waiting for osu!.exe to be extracted to AppData..."
        local TIMEOUT=0
        while [ ! -f "$EXPECTED_PATH" ]; do
            sleep 2
            TIMEOUT=$((TIMEOUT + 2))
            if [ $TIMEOUT -ge 180 ]; then
                log_warn "Extraction timeout. Checking for osu!.exe anyway..."
                break
            fi
        done

        wait $INSTALLER_PID 2>/dev/null || true  # Mono will assert/crash here — that's expected

        if [ -f "$EXPECTED_PATH" ]; then
            log_info "Extraction successful. Launching the game for first-time setup..."
            TARGET_OSU_EXE="$EXPECTED_PATH"
            env WINENTSYNC=0 WINEFSYNC=0 WINEESYNC=0 WINEWAYLAND=0 WAYLAND_DISPLAY="" \
                WINEPREFIX="$WINE_PREFIX" LC_ALL=en_US.UTF-8 \
                "$WINE_BIN" "$TARGET_OSU_EXE"
        else
            notify_error "osu!.exe not found after installation. The updater may have completely failed."
        fi

        log_info "Shutting down Wine prefix safely..."
        env WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" boot --end-session &>/dev/null || true
        env WINEPREFIX="$WINE_PREFIX" wineserver -k 2>/dev/null || true
        sleep 2
    else
        log_info "Existing osu! installation found at: $TARGET_OSU_EXE"
    fi

    if [ ! -f "$TARGET_OSU_EXE" ]; then
        notify_error "osu!.exe not found. Installation failed or was aborted by user."
    fi
    log_info "osu! located at: $TARGET_OSU_EXE"
}

create_system_integration() {
    log_info "Creating system integration files..."

    # 1. Icons
    local ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
    mkdir -p "$ICON_DIR"
    if [ ! -f "$ICON_DIR/osu-stable-game.png" ]; then
        # Icons are non-critical — log a warning if any fail, but don't abort the install.
        download "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Osu%21_Logo_2016.svg/512px-Osu%21_Logo_2016.svg.png" "$ICON_DIR/osu-stable-game.png"   || log_warn "Could not fetch osu-stable-game icon."
        download "https://img.icons8.com/ios11/512/228BE6/osu-lazer.png"                                                      "$ICON_DIR/osu-stable-map.png"    || log_warn "Could not fetch osu-stable-map icon."
        download "https://img.icons8.com/ios11/512/FAB005/osu-lazer.png"                                                      "$ICON_DIR/osu-stable-skin.png"   || log_warn "Could not fetch osu-stable-skin icon."
        download "https://img.icons8.com/ios11/512/7950F2/osu-lazer.png"                                                      "$ICON_DIR/osu-stable-replay.png" || log_warn "Could not fetch osu-stable-replay icon."
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    local CONFIG_DIR="$HOME/.config/osu-importer"
    mkdir -p "$CONFIG_DIR"

    # 2. Config file
    local CONFIG_FILE="$CONFIG_DIR/osu-env.conf"
    if [ -f "$CONFIG_FILE" ]; then
        local CONFIG_BAK="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$CONFIG_BAK"
        log_info "Existing config backed up to $CONFIG_BAK"
    fi
    cat > "$CONFIG_FILE" << EOF
# ==============================================================================
# osu! Linux Wrapper Configuration  (generated by osu! Installer v5.0.0)
# ==============================================================================

# --- Core Paths ---
WINE_PREFIX="$WINE_PREFIX"
WINE_BIN="$WINE_BIN"
OSU_LINUX="$TARGET_OSU_EXE"

# --- Localization ---
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# --- Sync (NTSync > Fsync > Esync, Wine picks best available) ---
# NTSync requires /dev/ntsync (Linux 6.8+).
# WARNING: Enabling sync with Wine Mono may cause crashes during loading screens.
EOF

    if [ "$ENABLE_FSYNC" = "TRUE" ]; then
        printf 'export WINENTSYNC=1\nexport WINEFSYNC=1\nexport WINEESYNC=1\n' >> "$CONFIG_FILE"
    else
        printf 'export WINENTSYNC=0\nexport WINEFSYNC=0\nexport WINEESYNC=0\n' >> "$CONFIG_FILE"
    fi

    cat >> "$CONFIG_FILE" << 'EOF'

# --- Audio Engine & Latency ---
# Lower buffer = better latency, higher = more stability.
EOF

    if [[ "$AUDIO_SELECTION" == *"ALSA"* ]]; then
        echo "export WINEAUDIODRIVER=alsa" >> "$CONFIG_FILE"
    else
        echo "export STAGING_AUDIO_DURATION=10000" >> "$CONFIG_FILE"
        echo "export PULSE_LATENCY_MSEC=60" >> "$CONFIG_FILE"
        if command -v pw-cli &> /dev/null; then
            echo 'export PIPEWIRE_LATENCY="1024/48000"' >> "$CONFIG_FILE"
        fi
    fi

    cat >> "$CONFIG_FILE" << 'EOF'

# --- Window System ---
# The driver is selected by the registry "Graphics" key (set at install time);
# WINEWAYLAND=1 alone does NOT switch it. Native Wayland needs WAYLAND_DISPLAY
# left intact -- only the X11 path blanks it to force XWayland.
EOF

    if [[ "$DRIVER_SELECTION" == *"Wayland"* ]]; then
        # Registry is "wayland,x11"; inherit WAYLAND_DISPLAY from the session.
        echo "export WINEWAYLAND=1" >> "$CONFIG_FILE"
    else
        echo "export WAYLAND_DISPLAY=''" >> "$CONFIG_FILE"
    fi

    cat >> "$CONFIG_FILE" << 'EOF'

# --- Optional Extras ---
# Uncomment to disable VSync in OpenGL:
# export vblank_mode=0

# --- Importer ---
# 1 = verbose import notifications (per-file / launching / rescan); 0 = quiet (errors + one summary).
export OSU_IMPORTER_DEBUG=0
EOF

    # Installer state — read back by --update to preserve user selections.
    # Don't edit by hand; re-run the installer to change.
    cat >> "$CONFIG_FILE" << EOF

# --- Installer state (used by --update; do not edit manually) ---
INSTALLER_WINE_SELECTION="$WINE_SELECTION"
INSTALLER_RENDERER_SELECTION="$RENDERER_SELECTION"
INSTALLER_DRIVER_SELECTION="$DRIVER_SELECTION"
INSTALLER_FONT_SELECTION="$FONT_SELECTION"
INSTALLER_DOTNET_SELECTION="$DOTNET_SELECTION"
INSTALLER_AUDIO_SELECTION="$AUDIO_SELECTION"
INSTALLER_INSTALL_RPC_BOOL="$INSTALL_RPC_BOOL"
INSTALLER_ENABLE_FSYNC="$ENABLE_FSYNC"
INSTALLER_ENABLE_GAMEMODE="$ENABLE_GAMEMODE"
INSTALLER_LINKS_DIR="$LINKS_DIR"
EOF

    # 3. Wrapper script
    local WRAPPER="$CONFIG_DIR/osu_importer_wrapper.sh"
    local GAMEMODE_ENABLED=""
    [ "$ENABLE_GAMEMODE" = "TRUE" ] && GAMEMODE_ENABLED="1"

    # Header: inject install-time choices (expanded now).
    cat > "$WRAPPER" << WEOF
#!/bin/bash
# osu! launcher + beatmap importer (generated by the installer -- edits are overwritten on --update).
# Native Wayland is switched via the registry "Graphics" key (set in configure_graphics);
# WINEWAYLAND=1 alone is a no-op. Beatmaps import ONLY into a fully-launched osu!.
GAMEMODE_ENABLED="$GAMEMODE_ENABLED"
WEOF

    # Body: static logic.
    cat >> "$WRAPPER" << 'WEOF'
set -u

CONFIG_FILE="$HOME/.config/osu-importer/osu-env.conf"
[ -f "$CONFIG_FILE" ] || { echo "osu-importer: config not found at $CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${WINE_PREFIX:?}" "${WINE_BIN:?}" "${OSU_LINUX:?}"
export WINEPREFIX="$WINE_PREFIX"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-$RUNTIME_DIR/.ydotool_socket}"

# hyprctl needs the instance signature when we're spawned from a file association.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$RUNTIME_DIR/hypr" ]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
    export HYPRLAND_INSTANCE_SIGNATURE
fi

WINEPATH_BIN="${WINE_BIN%/*}/winepath"
[ -x "$WINEPATH_BIN" ] || WINEPATH_BIN="winepath"

WINE_USER=$(ls -1 "$WINE_PREFIX/drive_c/users/" 2>/dev/null | grep -v '^Public$' | head -n1)
[ -n "$WINE_USER" ] || WINE_USER="$USER"
TEMP_LINUX="$WINE_PREFIX/drive_c/users/$WINE_USER/Temp"

SETTLE="${OSU_READY_SETTLE:-10}"   # grace for the beatmap subsystem after the window maps
DEBUG="${OSU_IMPORTER_DEBUG:-0}"   # 1 = verbose notifications (per-file / launching / rescan)

note() { notify-send "$@" 2>/dev/null || true; }                          # always shown
dbg()  { [ "${DEBUG:-0}" = 1 ] && notify-send "$@" 2>/dev/null || true; }  # only when DEBUG=1

osu_pid()       { pgrep -f 'osu!\.exe' | head -n1; }
osu_window_up() { hyprctl clients -j 2>/dev/null | grep -Eq '"class": *"osu!\.exe"'; }

ensure_wayland_env() {
    # Without WAYLAND_DISPLAY the driver silently falls back to XWayland.
    [ -n "${WAYLAND_DISPLAY:-}" ] && return 0
    local s
    s=$(ls "$RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -n1)
    [ -n "$s" ] && export WAYLAND_DISPLAY="$(basename "$s")"
}

launch_osu() {
    dbg "osu!" "Launching..."
    ensure_wayland_env
    local pre=""
    [ -n "$GAMEMODE_ENABLED" ] && command -v gamemoderun >/dev/null && pre="gamemoderun"
    ( $pre "$WINE_BIN" "$OSU_LINUX" >/dev/null 2>&1 & )
}

# Block until osu! is REALLY up: window mapped (UI live), then settle for the song db.
wait_until_ready() {
    local i
    if command -v hyprctl >/dev/null 2>&1; then
        for ((i=0; i<90; i++)); do
            osu_window_up && { sleep "$SETTLE"; return 0; }
            sleep 1
        done
        return 1
    fi
    # No compositor query: wait for the process, then a generous settle.
    for ((i=0; i<90; i++)); do [ -n "$(osu_pid)" ] && break; sleep 1; done
    [ -n "$(osu_pid)" ] || return 1
    sleep $(( SETTLE > 12 ? SETTLE : 12 )); return 0
}

import_file() {
    local file="$1" name win
    [ -f "$file" ] || return 1
    name="$(basename "$file")"
    mkdir -p "$TEMP_LINUX"
    cp -f "$file" "$TEMP_LINUX/$name" || return 1
    win=$("$WINEPATH_BIN" -w "$TEMP_LINUX/$name" 2>/dev/null | tr -d '\r')
    [ -n "$win" ] || { note -u critical "osu! Importer" "Bad path: $name"; return 1; }
    if "$WINE_BIN" "$OSU_LINUX" "$win" >/dev/null 2>&1; then
        [[ "$name" == *.osz ]] && rm -f "$file"
        dbg "osu! Importer" "Imported: $name"
    else
        note -u critical "osu! Importer" "Failed: $name"
        return 1
    fi
}

# Full Songs rescan = the in-game F5. osu! has no CLI/IPC rescan trigger and does NOT
# live-watch Songs, so a synthetic F5 is the only way that doesn't write into its memory
# (which its anti-cheat would flag). Effective ONLY on the song-select screen.
do_rescan() {
    if [ -z "$(osu_pid)" ]; then
        launch_osu          # a fresh start does a full Songs scan anyway
        return 0
    fi
    command -v ydotool >/dev/null || {
        note -u critical "osu!" "Rescan needs ydotool (+ ydotoold running)."
        return 1
    }
    # Best-effort focus; if it no-ops, rely on osu! already being focused.
    command -v hyprctl >/dev/null 2>&1 && { hyprctl dispatch focuswindow 'class:osu!.exe' >/dev/null 2>&1; sleep 0.25; }
    ydotool key 63:1 63:0   # KEY_F5
    dbg "osu!" "Rescan (F5) sent -- applies only on the song-select screen."
}

mkdir -p "$TEMP_LINUX"
find "$TEMP_LINUX" -type f -mmin +60 -delete 2>/dev/null || true

# Full rescan request.
case "${1:-}" in
    --rescan|--refresh) do_rescan; exit $? ;;
esac

# Pure launch (no files): start osu! if needed and bail.
if [ "$#" -eq 0 ]; then
    [ -n "$(osu_pid)" ] || launch_osu
    exit 0
fi

# Files present: guarantee a fully-ready osu! before importing into it.
if [ -z "$(osu_pid)" ]; then
    launch_osu
    if ! wait_until_ready; then
        note -u critical "osu! Importer" "osu! did not finish launching; nothing imported."
        exit 1
    fi
fi

# Split inputs: beatmaps (.osz) batch-import via Songs + one F5; skins/replays
# (.osk/.osr) only go through the per-file handoff.
osz=(); other=()
for file in "$@"; do
    [ -f "$file" ] || continue
    case "${file,,}" in
        *.osz) osz+=("$file") ;;
        *)     other+=("$file") ;;
    esac
done

# skins / replays: handoff each
for file in "${other[@]}"; do import_file "$file"; done

if [ "${#osz[@]}" -eq 1 ]; then
    import_file "${osz[0]}"
elif [ "${#osz[@]}" -gt 1 ]; then
    # Batch: drop extras LOOSE into Songs FIRST (so the rescan sees them in place),
    # then handoff the first for instant feedback, then one F5 to sweep the rest.
    SONGS="$(dirname "$OSU_LINUX")/Songs"
    mkdir -p "$SONGS"
    for file in "${osz[@]:1}"; do
        cp -f "$file" "$SONGS/" && rm -f "$file"
    done
    import_file "${osz[0]}"
    do_rescan
fi

_total=$(( ${#osz[@]} + ${#other[@]} ))
[ "$_total" -gt 0 ] && note "osu! Importer" "Imported $_total item(s)."
exit 0
WEOF
    chmod +x "$WRAPPER"

    # 4. Desktop entries
    cat > "$HOME/.local/share/applications/osu-stable.desktop" << EOF
[Desktop Entry]
Name=osu! (Stable)
Exec="$WRAPPER"
Icon=osu-stable-game
Type=Application
Categories=Game;
StartupWMClass=osu!.exe
EOF

    cat > "$HOME/.local/share/applications/osu-importer.desktop" << EOF
[Desktop Entry]
Name=osu! Importer
Exec="$WRAPPER" %F
Type=Application
Icon=osu-stable-game
MimeType=application/x-osu-beatmap;application/x-osu-skin;application/x-osu-replay;
NoDisplay=true
EOF

    # 5. MIME types
    mkdir -p "$HOME/.local/share/mime/packages"
    cat > "$HOME/.local/share/mime/packages/osu-file-types.xml" << 'EOF'
<?xml version="1.0"?>
<mime-info xmlns='http://www.freedesktop.org/standards/shared-mime-info'>
  <mime-type type="application/x-osu-beatmap">
    <comment>osu! beatmap</comment>
    <glob pattern="*.osz"/>
  </mime-type>
  <mime-type type="application/x-osu-skin">
    <comment>osu! skin</comment>
    <glob pattern="*.osk"/>
  </mime-type>
  <mime-type type="application/x-osu-replay">
    <comment>osu! replay</comment>
    <glob pattern="*.osr"/>
  </mime-type>
</mime-info>
EOF

    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    if command -v xdg-mime &> /dev/null; then
        xdg-mime default osu-importer.desktop application/x-osu-beatmap 2>/dev/null || true
        xdg-mime default osu-importer.desktop application/x-osu-skin    2>/dev/null || true
        xdg-mime default osu-importer.desktop application/x-osu-replay  2>/dev/null || true
    fi

    log_info "System integration complete."
}

create_osu_symlinks() {
    log_info "Creating convenience symlinks at $LINKS_DIR..."

    # Locate the osu! data directory inside the prefix
    local WINE_USER
    WINE_USER=$(ls -1 "$WINE_PREFIX/drive_c/users/" 2>/dev/null | grep -v "Public" | head -n 1)
    [ -z "$WINE_USER" ] && WINE_USER="$USER"
    local OSU_DATA_DIR="$WINE_PREFIX/drive_c/users/$WINE_USER/AppData/Local/osu!"

    if [ ! -d "$OSU_DATA_DIR" ]; then
        log_warn "osu! data directory not found at $OSU_DATA_DIR — skipping symlinks."
        return
    fi

    # Ensure target directories exist inside the prefix
    for dir in Songs Skins Logs Chat; do
        mkdir -p "$OSU_DATA_DIR/$dir"
    done

    mkdir -p "$LINKS_DIR"

    local TIMESTAMP
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local BACKED_UP=()
    local CREATED=0

    for dir in Songs Skins Logs Chat; do
        local LINK_PATH="$LINKS_DIR/$dir"
        local TARGET="$OSU_DATA_DIR/$dir"

        if [ -L "$LINK_PATH" ]; then
            # Already a symlink — update only if target differs
            local CURRENT_TARGET
            CURRENT_TARGET=$(readlink "$LINK_PATH")
            if [ "$CURRENT_TARGET" != "$TARGET" ]; then
                ln -sf "$TARGET" "$LINK_PATH"
                log_info "  Updated symlink: $LINK_PATH -> $TARGET"
            else
                log_info "  Already correct: $LINK_PATH"
            fi

        elif [ -d "$LINK_PATH" ]; then
            # Real directory — back it up, then move its contents into the prefix,
            # then replace with a symlink so the user doesn't lose any data.
            local BACKUP_PATH="${LINK_PATH}.bak.${TIMESTAMP}"
            log_warn "  $LINK_PATH is a real directory — backing up to $BACKUP_PATH"
            mv "$LINK_PATH" "$BACKUP_PATH"

            # Merge existing files into the prefix target so nothing is lost
            if [ -n "$(ls -A "$BACKUP_PATH" 2>/dev/null)" ]; then
                log_info "  Merging contents of $BACKUP_PATH into $TARGET ..."
                cp -rn "$BACKUP_PATH/." "$TARGET/" 2>/dev/null || true
            fi

            ln -s "$TARGET" "$LINK_PATH"
            BACKED_UP+=("$dir -> $BACKUP_PATH")
            CREATED=$((CREATED + 1))
            log_info "  Created symlink: $LINK_PATH -> $TARGET"

        elif [ -e "$LINK_PATH" ]; then
            # Regular file with that name — unusual, just warn
            log_warn "  $LINK_PATH is a regular file — skipping to avoid data loss."

        else
            ln -s "$TARGET" "$LINK_PATH"
            log_info "  Created: $LINK_PATH -> $TARGET"
            CREATED=$((CREATED + 1))
        fi
    done

    # Report backups to the user
    if [ ${#BACKED_UP[@]} -gt 0 ]; then
        local BAK_MSG="The following directories were backed up before symlinking:\n"
        for entry in "${BACKED_UP[@]}"; do
            BAK_MSG="$BAK_MSG  • $entry\n"
        done
        BAK_MSG="${BAK_MSG}\nTheir contents were merged into the Wine prefix.\nYou can safely delete the .bak folders once you've verified everything is intact."
        log_warn "$BAK_MSG"
        if [ "$SILENT_MODE" = false ]; then
            notify_warning "$BAK_MSG"
        fi
    fi

    if [ $CREATED -gt 0 ]; then
        log_info "Symlinks ready at: $LINKS_DIR"
    fi
}
