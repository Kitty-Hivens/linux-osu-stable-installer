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

# Where osu! extracts itself. The Wine user directory is whatever name the prefix was
# created with, so it is read back from the prefix rather than assumed to be $USER.
osu_expected_exe() {
    local wine_user
    wine_user=$(ls -1 "$WINE_PREFIX/drive_c/users/" 2>/dev/null | grep -v "Public" | head -n 1)
    [ -z "$wine_user" ] && wine_user="$USER"
    printf '%s' "$WINE_PREFIX/drive_c/users/$wine_user/AppData/Local/osu!/osu!.exe"
}

# Path of the self-extracting bootstrapper inside the prefix.
OSU_BOOTSTRAP_EXE=""

# osu! ships as a bootstrapper that unpacks the client and downloads the game on its first
# run. That run belongs to the first launch, which the wrapper handles, so installing never
# has to open a window and wait for someone to close it. The bootstrapper is fetched here
# but deliberately not executed: the launcher icon is read out of it, and having it on disk
# means the first launch has one less thing that can fail.
prepare_osu_client() {
    log_info "Checking for an existing osu! installation..."

    OSU_BOOTSTRAP_EXE="$WINE_PREFIX/osu!install.exe"
    TARGET_OSU_EXE=$(osu_expected_exe)

    if [ ! -f "$TARGET_OSU_EXE" ]; then
        # Prefixes from earlier versions may hold osu! somewhere else.
        local FOUND
        FOUND=$(find "$WINE_PREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)
        [ -n "$FOUND" ] && TARGET_OSU_EXE="$FOUND"
    fi

    if [ -f "$TARGET_OSU_EXE" ]; then
        log_info "Existing osu! installation found at: $TARGET_OSU_EXE"
    else
        log_info "osu! is not unpacked yet -- the first launch will do it, at: $TARGET_OSU_EXE"
    fi

    # A bootstrapper left behind by an interrupted transfer exists and is non-empty, yet Wine
    # would refuse it -- so what is already on disk gets the same check as a fresh download.
    if [ -f "$OSU_BOOTSTRAP_EXE" ] && ! is_pe "$OSU_BOOTSTRAP_EXE"; then
        log_warn "Stored osu!install.exe is not a Windows executable -- discarded."
        rm -f "$OSU_BOOTSTRAP_EXE"
    fi

    if [ ! -f "$OSU_BOOTSTRAP_EXE" ]; then
        log_info "Fetching the osu! bootstrapper (not executed here)..."
        if download "https://m1.ppy.sh/r/osu!install.exe" "$OSU_BOOTSTRAP_EXE" \
            && ! is_pe "$OSU_BOOTSTRAP_EXE"; then
            rm -f "$OSU_BOOTSTRAP_EXE"
            log_warn "What m1.ppy.sh returned is not a Windows executable -- discarded."
        fi
        [ -f "$OSU_BOOTSTRAP_EXE" ] \
            || log_warn "Could not fetch osu!install.exe -- the first launch will retry the download."
    fi

    # osu! keeps directories that already exist, so creating them now is what lets the
    # convenience symlinks point at something before the game has ever run.
    local DATA_DIR dir
    DATA_DIR=$(dirname "$TARGET_OSU_EXE")
    for dir in Songs Skins Logs Chat; do
        mkdir -p "$DATA_DIR/$dir"
    done
}

ICON_BASE="$HOME/.local/share/icons/hicolor"

# True if icon $1 is already installed under any size directory.
_icon_present() {
    local f
    for f in "$ICON_BASE"/*/apps/"$1".png; do
        [ -f "$f" ] && return 0
    done
    return 1
}

# Install PNG $1 under icon name $2, into the hicolor directory matching its real pixel
# size. Sizes outside the standard set are squared off to 128 when ImageMagick is around;
# without it the file is left where it is rather than lying about its size.
_install_icon() {
    local src="$1" name="$2" size dir im old
    is_png "$src" || return 1
    size=$(png_size "$src") || return 1
    case "$size" in
        16x16|22x22|24x24|32x32|48x48|64x64|72x72|96x96|128x128|192x192|256x256|512x512) ;;
        *)
            im=$(command -v magick || command -v convert) || return 1
            "$im" "$src" -resize 128x128 -background none -gravity center -extent 128x128 "$src" >/dev/null 2>&1 || return 1
            size="128x128"
            ;;
    esac
    dir="$ICON_BASE/$size/apps"
    mkdir -p "$dir" || return 1
    # Drop other size variants so a re-install cannot leave a stale copy shadowing this one.
    for old in "$ICON_BASE"/*/apps/"$name".png; do
        [ -f "$old" ] && [ "$old" != "$dir/$name.png" ] && rm -f "$old"
    done
    cp -f "$src" "$dir/$name.png"
}

# Pull the largest icon out of Windows executable $1 into PNG $2. Needs icoutils.
_extract_exe_icon() {
    local exe="$1" out="$2" tmp ico png sz area best best_area
    command -v wrestool >/dev/null 2>&1 && command -v icotool >/dev/null 2>&1 || return 1
    [ -f "$exe" ] || return 1
    tmp=$(mktemp -d) || return 1

    wrestool -x -t 14 -o "$tmp" "$exe" >/dev/null 2>&1
    for ico in "$tmp"/*.ico; do
        [ -f "$ico" ] && icotool -x -o "$tmp" "$ico" >/dev/null 2>&1
    done

    best=""; best_area=0
    for png in "$tmp"/*.png; do
        [ -f "$png" ] || continue
        sz=$(png_size "$png") || continue
        area=$(( ${sz%x*} * ${sz#*x} ))
        if [ "$area" -gt "$best_area" ]; then best_area=$area; best="$png"; fi
    done

    if [ -n "$best" ]; then
        cp -f "$best" "$out" && rm -rf "$tmp" && return 0
    fi
    rm -rf "$tmp"
    return 1
}

# Install the launcher and file-type icons, skipping any already present. The launcher icon
# is taken from osu!.exe when icoutils is available -- it always matches the installed build.
# Before the first launch there is no osu!.exe yet, and the bootstrapper carries the same
# icon set, so it serves as the source instead; a download is the last resort. Failures are non-fatal but
# set ICON_INSTALL_FAILED so the installation summary can report them.
install_icons() {
    local tmp pair name color
    tmp=$(mktemp -d) || { log_warn "Could not create a temp directory for icons."; ICON_INSTALL_FAILED=true; return 0; }

    if _icon_present osu-stable-game; then
        log_info "  Application icon already installed."
    elif _extract_exe_icon "${TARGET_OSU_EXE:-}" "$tmp/osu-stable-game.png" \
        || _extract_exe_icon "${OSU_BOOTSTRAP_EXE:-$WINE_PREFIX/osu!install.exe}" "$tmp/osu-stable-game.png" \
        || download_png "$tmp/osu-stable-game.png" \
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Osu%21_Logo_2016.svg/500px-Osu%21_Logo_2016.svg.png" \
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Osu%21_Logo_2016.svg/250px-Osu%21_Logo_2016.svg.png"
    then
        _install_icon "$tmp/osu-stable-game.png" osu-stable-game \
            || { log_warn "Could not install the osu! application icon."; ICON_INSTALL_FAILED=true; }
    else
        log_warn "Could not obtain the osu! application icon (install icoutils to extract it from osu!.exe)."
        ICON_INSTALL_FAILED=true
    fi

    for pair in "osu-stable-map 228BE6" "osu-stable-skin FAB005" "osu-stable-replay 7950F2"; do
        IFS=' ' read -r name color <<< "$pair"
        _icon_present "$name" && continue
        if download_png "$tmp/$name.png" "https://img.icons8.com/ios11/512/$color/osu-lazer.png"; then
            _install_icon "$tmp/$name.png" "$name" \
                || { log_warn "Could not install the $name icon."; ICON_INSTALL_FAILED=true; }
        else
            log_warn "Could not fetch the $name icon."
            ICON_INSTALL_FAILED=true
        fi
    done

    rm -rf "$tmp"
}

# Warning line for the closing report; empty when every icon landed.
icon_status_note() {
    [ "${ICON_INSTALL_FAILED:-false}" = true ] || return 0
    printf '%s' "Some icons could not be installed -- affected menu and file-type entries will show a placeholder.
Re-run with --update to retry once the sources are reachable."
}

# Refresh what desktop environments actually read. GTK uses icon-theme.cache; KDE keeps
# .desktop entries -- icon name included -- in ksycoca and keeps showing the stale entry
# until that is rebuilt.
refresh_desktop_caches() {
    gtk-update-icon-cache -f -t "$ICON_BASE" 2>/dev/null || true
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
        kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
    fi
}

create_system_integration() {
    log_info "Creating system integration files..."

    # The desktop entry and the file associations are handled by the host, which has no
    # Wine of its own in container mode -- point them at shims that reach into the container.
    if [ "${DISTROBOX_MODE:-false}" = true ]; then
        write_container_shims
    fi

    # 1. Icons
    install_icons

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
# osu! Linux Wrapper Configuration  (generated by osu! Installer v5.1.1)
# ==============================================================================

# --- Core Paths ---
# In container mode WINE_BIN is a host shim that runs the container's Wine; the wrapper
# derives winepath from the same directory, so both have to live side by side.
WINE_PREFIX="$WINE_PREFIX"
WINE_BIN="${WINE_BIN_HOST:-$WINE_BIN}"
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
    # An empty container name is what tells a later run this is a plain host installation.
    local STORED_BOX=""
    [ "${DISTROBOX_MODE:-false}" = true ] && STORED_BOX="$DISTROBOX_NAME"
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
INSTALLER_DISTROBOX_NAME="$STORED_BOX"
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

# Launched from a desktop entry there is no terminal to print to, and a notification is gone
# the moment it times out -- so everything the user is told is also written here, along with
# Wine's own output from the one step that downloads anything.
WRAPPER_LOG="$HOME/.osu_wrapper.log"
if [ -f "$WRAPPER_LOG" ] && [ "$(stat -c%s "$WRAPPER_LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$WRAPPER_LOG" "$WRAPPER_LOG.1" 2>/dev/null || true
fi
wlog() { printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$WRAPPER_LOG" 2>/dev/null || true; }

note() {                                                                  # always shown
    local msg=("$@")
    [ "${msg[0]:-}" = "-u" ] && msg=("${msg[@]:2}")   # urgency flag is not part of the text
    wlog "${msg[*]}"
    notify-send "$@" 2>/dev/null || true
}
dbg()  { wlog "$*"; [ "${DEBUG:-0}" = 1 ] && notify-send "$@" 2>/dev/null || true; }  # notified only when DEBUG=1

# Wine sets the process name to osu!.exe, so that is what identifies a real client. The
# loose command-line form matches anything that merely mentions the executable -- a terminal
# it was typed in, an editor, a script -- and a false hit makes the launcher below decide the
# game is already running and silently do nothing. The fallback keeps the backslash of the
# Windows path Wine actually passes, which no Linux path can contain.
osu_pid() {
    local p
    p=$(pgrep -x 'osu!\.exe' 2>/dev/null | head -n1)
    [ -n "$p" ] || p=$(pgrep -f 'osu!\\osu!\.exe' 2>/dev/null | head -n1)
    printf '%s' "$p"
}
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

# osu! ships as a self-extracting bootstrapper, and running it is what unpacks the client
# and pulls the game down. The installer deliberately leaves that to the first launch, so
# everything below has to be prepared to find no osu!.exe at all yet.
BOOTSTRAP_LOCK_HELD=0

# Every Windows executable starts with "MZ". A captive portal or an error page answers with
# HTTP 200 and would pass a size check, only to fail later as Wine refusing the file.
_is_pe() {
    [ -s "$1" ] || return 1
    [ "$(head -c 2 "$1" 2>/dev/null)" = "MZ" ]
}

# Drop the bootstrap lock and the descriptor carrying it. Safe to call when no lock is held.
_release_bootstrap_lock() {
    [ "${BOOTSTRAP_LOCK_HELD:-0}" = 1 ] || return 0
    flock -u 9 2>/dev/null || true
    exec 9>&-
    BOOTSTRAP_LOCK_HELD=0
}

ensure_osu_installed() {
    [ -f "$OSU_LINUX" ] && return 0

    # Selecting several beatmaps at once starts one wrapper per file, and the launcher can
    # be clicked twice. Two bootstrappers unpacking into the same prefix would corrupt it.
    # Opening the lock is attempted first: taking flock on a descriptor that never opened
    # would fail and be reported as a busy install, hiding the real reason.
    local lock="$WINE_PREFIX/.osu-bootstrap.lock"
    if command -v flock > /dev/null 2>&1 && : > "$lock" 2>/dev/null; then
        exec 9> "$lock"
        BOOTSTRAP_LOCK_HELD=1
        if ! flock -w 900 9; then
            note -u critical "osu!" "Another launch is still installing osu!. Try again once it finishes."
            _release_bootstrap_lock
            return 1
        fi
        # The invocation we waited for may have completed the job already.
        if [ -f "$OSU_LINUX" ]; then
            _release_bootstrap_lock
            return 0
        fi
    fi

    local boot="$WINE_PREFIX/osu!install.exe"
    # Whatever is already on disk is validated too, not just a fresh download: an interrupted
    # transfer leaves a file that exists, is non-empty, and is not an executable.
    if [ -f "$boot" ] && ! _is_pe "$boot"; then
        wlog "discarding a stored osu!install.exe that is not a Windows executable"
        rm -f "$boot"
    fi

    if [ ! -f "$boot" ]; then
        note "osu!" "Downloading the osu! installer..."
        if command -v curl > /dev/null 2>&1; then
            curl -L --fail -sS -o "$boot" "https://m1.ppy.sh/r/osu!install.exe" >> "$WRAPPER_LOG" 2>&1
        elif command -v wget > /dev/null 2>&1; then
            wget -q -O "$boot" "https://m1.ppy.sh/r/osu!install.exe" >> "$WRAPPER_LOG" 2>&1
        else
            wlog "neither curl nor wget is installed"
        fi
        if ! _is_pe "$boot"; then
            wlog "download failed or did not return a Windows executable"
            rm -f "$boot"
            note -u critical "osu!" "Could not download the osu! installer. Check your connection, then see $WRAPPER_LOG"
            _release_bootstrap_lock
            return 1
        fi
    fi

    note "osu!" "First launch: osu! is unpacking and updating itself. The updater window may vanish at 100% -- it comes back on its own."

    # A flock lives on the open file description, so any process inheriting the descriptor
    # keeps holding it. The bootstrapper hands over to the client, which would then hold the
    # lock for the whole game session and make every other launch wait it out -- 9>&- closes
    # the descriptor in the child so only this function owns the lock.
    #
    # Sync primitives are what makes the Wine Mono updater assert during this step, and the
    # updater behaves better on XWayland than on the native driver. Wine's output is kept:
    # it is the only diagnostic there is when the unpack does not finish.
    ( WINEPREFIX="$WINE_PREFIX" WINENTSYNC=0 WINEFSYNC=0 WINEESYNC=0 \
      WINEWAYLAND=0 WAYLAND_DISPLAY="" LC_ALL=en_US.UTF-8 \
      "$WINE_BIN" "$boot" >> "$WRAPPER_LOG" 2>&1 9>&- ) &
    local boot_pid=$!

    local waited=0
    while [ ! -f "$OSU_LINUX" ]; do
        sleep 2
        waited=$((waited + 2))
        [ $((waited % 30)) -eq 0 ] && wlog "still unpacking, ${waited}s elapsed"
        # A bootstrapper that died without producing the client will never produce it;
        # waiting out the full deadline would only hide the reason for a quarter of an hour.
        if ! kill -0 "$boot_pid" 2>/dev/null; then
            sleep 3
            [ -f "$OSU_LINUX" ] && break
            note -u critical "osu!" "The osu! installer stopped without unpacking the game. Details: $WRAPPER_LOG"
            _release_bootstrap_lock
            return 1
        fi
        if [ "$waited" -ge 900 ]; then
            note -u critical "osu!" "osu! did not finish unpacking after 15 minutes. Details: $WRAPPER_LOG"
            _release_bootstrap_lock
            return 1
        fi
    done
    wlog "osu! unpacked to $OSU_LINUX after ${waited}s"

    # Other launches only need to wait for the client to exist, not for it to be ready --
    # the readiness wait is theirs to do, and holding the lock longer would stall them.
    _release_bootstrap_lock

    # osu!.exe exists a moment before the bootstrapper hands over to it and exits. Returning
    # in that gap would leave the launcher below convinced nothing is running, and a second
    # client started on top of the first makes the two fight over osu!.db and the user config.
    local settle=0
    while [ "$settle" -lt 30 ]; do
        [ -n "$(osu_pid)" ] && { wlog "the bootstrapper started the client itself"; break; }
        kill -0 "$boot_pid" 2>/dev/null || { sleep 3; break; }
        sleep 1
        settle=$((settle + 1))
    done

    return 0
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

require_ready() {
    wait_until_ready && return 0
    note -u critical "osu! Importer" "osu! did not finish launching; nothing imported."
    exit 1
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
        # Handing a file to the client can be refused while it is still setting itself up.
        # A beatmap does not need the client for that: dropped into Songs it is picked up by
        # the next full scan, which any restart performs anyway. Losing the file is the one
        # outcome that would be unacceptable.
        if [[ "${name,,}" == *.osz ]]; then
            local songs="$(dirname "$OSU_LINUX")/Songs"
            mkdir -p "$songs"
            if cp -f "$file" "$songs/"; then
                rm -f "$file"
                note "osu! Importer" "$name could not be handed to osu! -- queued in Songs, it appears after a restart or F5."
                return 0
            fi
        fi
        note -u critical "osu! Importer" "Failed: $name -- see $WRAPPER_LOG"
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
    # A Lua Hyprland config parses the dispatch argument as Lua, so the classic form reaches
    # it as a syntax error; a legacy config understands only the classic form. hyprctl exits
    # 0 for both, so the reply text is the only thing that separates them. The classic form
    # runs first because it is the one already working on a legacy config -- probing with it
    # means a wrong guess about the reply text cannot take away a focus that works today.
    if command -v hyprctl >/dev/null 2>&1; then
        case "$(hyprctl dispatch focuswindow 'class:osu!.exe' 2>&1)" in
            error:*) hyprctl dispatch 'hl.dsp.focus({ window = "class:osu!.exe" })' >/dev/null 2>&1 ;;
        esac
        sleep 0.25
    fi
    ydotool key 63:1 63:0   # KEY_F5
    dbg "osu!" "Rescan (F5) sent -- applies only on the song-select screen."
}

mkdir -p "$TEMP_LINUX"
find "$TEMP_LINUX" -type f -mmin +60 -delete 2>/dev/null || true

ensure_osu_installed || exit 1

# Full rescan request.
case "${1:-}" in
    --rescan|--refresh) do_rescan; exit $? ;;
esac

# Pure launch (no files): start osu! if needed and bail.
if [ "$#" -eq 0 ]; then
    [ -n "$(osu_pid)" ] || launch_osu
    exit 0
fi

# Files present: guarantee a fully-ready osu! before importing into it. A client that is
# already up is taken at its word -- nothing osu! exposes says whether it is done setting
# itself up, and a handoff it refuses is caught below rather than guessed at here.
if [ -z "$(osu_pid)" ]; then
    launch_osu
    require_ready
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
[ "$_total" -gt 0 ] && dbg "osu! Importer" "Imported $_total item(s)."
exit 0
WEOF
    chmod +x "$WRAPPER"

    # 4. Desktop entries
    mkdir -p "$HOME/.local/share/applications"
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
    # Drop MIME packages from older installer versions so they don't shadow this one.
    rm -f "$HOME/.local/share/mime/packages/osu-importer.xml" \
          "$HOME/.local/share/mime/packages/osu-stable-importer.xml"
    cat > "$HOME/.local/share/mime/packages/osu-file-types.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns='http://www.freedesktop.org/standards/shared-mime-info'>
  <mime-type type="application/x-osu-beatmap">
    <comment>osu! beatmap</comment>
    <sub-class-of type="application/zip"/>
    <glob pattern="*.osz"/>
    <icon name="osu-stable-map"/>
  </mime-type>
  <mime-type type="application/x-osu-skin">
    <comment>osu! skin</comment>
    <sub-class-of type="application/zip"/>
    <glob pattern="*.osk"/>
    <icon name="osu-stable-skin"/>
  </mime-type>
  <mime-type type="application/x-osu-replay">
    <comment>osu! replay</comment>
    <glob pattern="*.osr"/>
    <icon name="osu-stable-replay"/>
  </mime-type>
</mime-info>
EOF

    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    if command -v xdg-mime &> /dev/null; then
        xdg-mime default osu-importer.desktop application/x-osu-beatmap 2>/dev/null || true
        xdg-mime default osu-importer.desktop application/x-osu-skin    2>/dev/null || true
        xdg-mime default osu-importer.desktop application/x-osu-replay  2>/dev/null || true
    fi

    refresh_desktop_caches

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
