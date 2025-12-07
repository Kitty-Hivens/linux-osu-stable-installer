#!/bin/bash
# ==============================================================================
# osu! Linux Installer (Stable)
# Version: v4.0.0 (Universal YAD Edition)
#
# Author:  Kitty-Hivens
# GitHub:  https://github.com/Kitty-Hivens/linux-osu-stable-installer
# License: MIT
#
# Supports: Arch, Debian, Fedora, Void Linux, NixOS (manual dept)
# UI:       YAD (Yet Another Dialog) Dashboard
# ==============================================================================

set -e

# --- 0. Bootstrap YAD ---

if [ -f "/etc/NIXOS" ] || (grep -q "NixOS" /etc/os-release 2>/dev/null); then
    if ! command -v yad &> /dev/null; then
        echo "Error: NixOS detected. Please install 'yad' manually."
        exit 1
    fi
fi

if ! command -v yad &> /dev/null; then
    echo "Installing YAD..."
    if command -v pacman &> /dev/null; then
        pkexec pacman -S yad --noconfirm
    elif command -v apt &> /dev/null; then
        pkexec apt update && pkexec apt install -y yad
    elif command -v dnf &> /dev/null; then
        pkexec dnf install -y yad
    elif command -v xbps-install &> /dev/null; then
        pkexec xbps-install -S -y yad
    else
        echo "Error: Package manager not found. Install 'yad' manually."
        exit 1
    fi
fi

# --- GUI Helpers ---

SCRIPT_TITLE="osu! Installer v4.0"
ICON="applications-games"

notify_user() { yad --title="$SCRIPT_TITLE" --text="$1" --image="$ICON" --button="OK:0" --center --width=350; }
notify_error() { yad --title="Error" --text="$1" --image="dialog-error" --button="Exit:1" --center --width=350; exit 1; }
notify_warning() { yad --title="Warning" --text="$1" --image="dialog-warning" --button="OK:0" --center --width=350; }

# --- 1. Dashboard (Configuration) ---

# Defaults
DEFAULT_PREFIX="$HOME/.wine-osu"
if [ -d "$HOME/.osu-wine" ]; then DEFAULT_PREFIX="$HOME/.osu-wine"; fi

BEST_WINE="wine"
if command -v wine-staging &> /dev/null; then BEST_WINE="wine-staging"; fi

# Form
VALUES=$(yad --form --center --width=550 --title="$SCRIPT_TITLE" \
    --window-icon="$ICON" --image="$ICON" \
    --text="<b>Configuration Dashboard</b>\nSelect installation parameters:" \
    --field="Install Location:DIR" "$DEFAULT_PREFIX" \
    --field="Wine Binary:CB" "$BEST_WINE!Custom Path" \
    --field="Graphics API:CB" "OpenGL (Stable)!DXVK (Low Latency)" \
    --field="Window Driver:CB" "X11 (Recommended)!Wayland (Experimental)" \
    --field="Fonts:CB" "WenQuanYi (Micro Hei)!Noto Sans CJK!Koruri!System Links!Skip" \
    --field="Install Discord RPC:CHK" "TRUE" \
    --separator="|")

if [ $? -ne 0 ] || [ -z "$VALUES" ]; then
    echo "Installation cancelled."
    exit 0
fi

IFS="|" read -r WINE_PREFIX WINE_SELECTION RENDERER_SELECTION DRIVER_SELECTION FONT_SELECTION INSTALL_RPC_BOOL <<< "$VALUES"

# --- 2. Dependency Check & System Setup ---

NEEDS_INSTALL=""
DRIVERS_INSTALLED=false

for pkg in curl unzip winetricks; do
    if ! command -v $pkg &> /dev/null; then NEEDS_INSTALL="$NEEDS_INSTALL $pkg"; fi
done

# Wine Check
WINE_BIN=""
if [ "$WINE_SELECTION" = "Custom Path" ]; then
    WINE_BIN=$(yad --file-selection --title="Select Wine Executable" --file-filter="Executable | wine")
    if [ -z "$WINE_BIN" ]; then exit 1; fi
else
    if ! command -v "$WINE_SELECTION" &> /dev/null; then
        NEEDS_INSTALL="$NEEDS_INSTALL $WINE_SELECTION"
    fi
    WINE_BIN=$(command -v "$WINE_SELECTION" || echo "$WINE_SELECTION")
fi

# Void Linux Specifics
if command -v xbps-install &> /dev/null; then
    if ! xbps-query -l | grep -q "wine-32bit"; then NEEDS_INSTALL="$NEEDS_INSTALL wine-32bit"; fi
    if ! xbps-query -l | grep -q "libglvnd-32bit"; then NEEDS_INSTALL="$NEEDS_INSTALL libglvnd-32bit"; fi

    # NVIDIA Check
    if command -v nvidia-smi &> /dev/null || (lspci 2>/dev/null | grep -i "nvidia" &> /dev/null); then
         if ! xbps-query -l | grep -q "nvidia-libs-32bit"; then NEEDS_INSTALL="$NEEDS_INSTALL nvidia-libs-32bit"; fi
    else
         if ! xbps-query -l | grep -q "mesa-dri-32bit"; then NEEDS_INSTALL="$NEEDS_INSTALL mesa-dri-32bit"; fi
    fi

    # Fonts dependencies
    for lib in pango-32bit cairo-32bit libXft-32bit freetype-32bit fontconfig-32bit libxml2-32bit harfbuzz-32bit; do
        if ! xbps-query -l | grep -q "$lib"; then NEEDS_INSTALL="$NEEDS_INSTALL $lib"; fi
    done
fi

if [ -n "$NEEDS_INSTALL" ]; then
    notify_user "Installing dependencies:\n$NEEDS_INSTALL"

    if command -v pacman &> /dev/null; then
        pkexec pacman -S $NEEDS_INSTALL --noconfirm
        DRIVERS_INSTALLED=true
    elif command -v apt &> /dev/null; then
        pkexec apt install -y $NEEDS_INSTALL
        DRIVERS_INSTALLED=true
    elif command -v dnf &> /dev/null; then
        pkexec dnf install -y $NEEDS_INSTALL
        DRIVERS_INSTALLED=true
    elif command -v xbps-install &> /dev/null; then
        if [[ "$NEEDS_INSTALL" == *"nvidia"* ]] && ! xbps-query -L | grep -q "nonfree"; then
             pkexec xbps-install -Sy void-repo-nonfree
        fi
        if ! xbps-query -L | grep -q "multilib"; then
             pkexec xbps-install -Sy void-repo-multilib
        fi
        pkexec xbps-install -Sy $NEEDS_INSTALL
        DRIVERS_INSTALLED=true
    fi
fi

if [ "$DRIVERS_INSTALLED" = true ]; then
    notify_warning "System drivers updated.\nPlease reboot and run script again."
    exit 0
fi

if [ -z "$WINE_BIN" ] && command -v "$WINE_SELECTION" &> /dev/null; then
    WINE_BIN=$(command -v "$WINE_SELECTION")
fi

export WINE="$WINE_BIN"
export WINEPREFIX="$WINE_PREFIX"

# --- 3. Prefix & .NET Setup ---

mkdir -p "$WINE_PREFIX"

if [ ! -d "$WINE_PREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319" ]; then
    (
      set +e
      WAYLAND_DISPLAY="" winetricks -q dotnet48
      set -e
    ) | yad --progress --pulsate --auto-close --no-cancel \
        --title="Installing .NET" --text="Installing .NET 4.8 Framework..." \
        --center --width=400
fi

# --- 4. Graphics Configuration ---

(
  # Renderer
  if [[ "$RENDERER_SELECTION" == *"DXVK"* ]]; then
      echo "Installing DXVK..."
      winetricks -q dxvk
  else
      echo "Reverting to OpenGL..."
      "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d9" /f 2>/dev/null || true
      "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "dxgi" /f 2>/dev/null || true
      "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d11" /f 2>/dev/null || true
  fi

  # Driver
  if [[ "$DRIVER_SELECTION" == *"Wayland"* ]]; then
      echo "Enabling Wayland Driver..."
      "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /f 2>/dev/null
      "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /v "Graphics" /t REG_SZ /d "wayland" /f
  else
      echo "Enforcing X11 Driver..."
      "$WINE_BIN" reg delete "HKCU\Software\Wine\Drivers" /v "Graphics" /f 2>/dev/null || true
  fi

) | yad --progress --pulsate --auto-close --title="Graphics" --text="Applying graphics settings..." --center

# --- 5. Fonts ---

if [[ "$FONT_SELECTION" != "Skip" ]]; then
    FONT_DIR="$WINE_PREFIX/drive_c/windows/Fonts"
    mkdir -p "$FONT_DIR"
    rm -f "$FONT_DIR/"*

    (
    case "$FONT_SELECTION" in
      "WenQuanYi"*)
        echo "Downloading WenQuanYi..."
        curl -L -o "$FONT_DIR/wqy-microhei.ttc" "https://github.com/anthonyfok/fonts-wqy-microhei/raw/master/wqy-microhei.ttc"
        cat > "$WINE_PREFIX/font_fix.reg" << EOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="WenQuanYi Micro Hei"
"Segoe UI"="WenQuanYi Micro Hei"
"MS Gothic"="WenQuanYi Micro Hei"
"Meiryo"="WenQuanYi Micro Hei"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"WenQuanYi Micro Hei (TrueType)"="wqy-microhei.ttc"
EOF
        ;;
      "Noto Sans"*)
        echo "Downloading Noto Sans..."
        curl -L -o "$FONT_DIR/osu-font.otf" "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
        cat > "$WINE_PREFIX/font_fix.reg" << EOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="Noto Sans CJK JP Regular"
"Segoe UI"="Noto Sans CJK JP Regular"
"MS Gothic"="Noto Sans CJK JP Regular"
"Meiryo"="Noto Sans CJK JP Regular"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"Noto Sans CJK JP Regular (TrueType)"="osu-font.otf"
EOF
        ;;
      "Koruri"*)
        echo "Downloading Koruri..."
        cd "$FONT_DIR"
        curl -L -o koruri.tar.xz "https://github.com/Koruri/Koruri/releases/download/20210720/Koruri-20210720.tar.xz"
        tar -xf koruri.tar.xz
        find . -name "Koruri-Regular.ttf" -exec mv {} . \;
        rm -rf Koruri-* koruri.tar.xz
        cat > "$WINE_PREFIX/font_fix.reg" << EOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="Koruri Regular"
"Segoe UI"="Koruri Regular"
"MS Gothic"="Koruri Regular"
"Meiryo"="Koruri Regular"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"Koruri Regular (TrueType)"="Koruri-Regular.ttf"
EOF
        ;;
      "System"*)
        echo "Linking System Fonts..."
        find /usr/share/fonts -type f \( -name "*.ttf" -o -name "*.otf" \) -exec ln -s {} "$FONT_DIR" \; 2>/dev/null || true
        find "$HOME/.local/share/fonts" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec ln -s {} "$FONT_DIR" \; 2>/dev/null || true
        echo "REGEDIT4" > "$WINE_PREFIX/font_fix.reg"
        ;;
    esac

    # Global Smoothing
    cat >> "$WINE_PREFIX/font_fix.reg" << EOF
[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001
"FontSmoothingType"=dword:00000002
[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Nls\CodePage]
"932"="cp932.nls"
"00000411"="cp932.nls"
EOF
    WAYLAND_DISPLAY="" "$WINE_BIN" regedit "$WINE_PREFIX/font_fix.reg" 2>/dev/null
    rm "$WINE_PREFIX/font_fix.reg"
    ) | yad --progress --pulsate --auto-close --no-cancel --title="Fonts" --text="Installing fonts..." --center
fi

# --- 6. RPC Setup ---

if [ "$INSTALL_RPC_BOOL" = "TRUE" ]; then
    (
    echo "Cleaning old bridge..."
    WAYLAND_DISPLAY="" "$WINE_BIN" net stop rpc-bridge 2>/dev/null || true
    WAYLAND_DISPLAY="" "$WINE_BIN" taskkill /IM bridge.exe /F 2>/dev/null || true
    rm -f "$WINE_PREFIX/drive_c/windows/bridge.exe"

    echo "Downloading RPC Bridge..."
    TEMP_DIR="$WINE_PREFIX/drive_c/windows/temp_bridge"
    mkdir -p "$TEMP_DIR"
    curl -L -o "$TEMP_DIR/bridge.zip" "https://github.com/EnderIce2/rpc-bridge/releases/latest/download/bridge.zip"
    unzip -o "$TEMP_DIR/bridge.zip" -d "$TEMP_DIR"

    BRIDGE_EXE=$(find "$TEMP_DIR" -name "bridge.exe" | head -n 1)
    if [ -n "$BRIDGE_EXE" ]; then
        WAYLAND_DISPLAY="" "$WINE_BIN" "$BRIDGE_EXE" --install
    fi
    rm -rf "$TEMP_DIR"
    ) | yad --progress --pulsate --auto-close --title="Discord RPC" --text="Installing Rich Presence..." --center
fi

# --- 7. Install osu! ---

TARGET_OSU_EXE=$(find "$WINE_PREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)

if [ -z "$TARGET_OSU_EXE" ]; then
    curl -L -o "$WINE_PREFIX/osu!install.exe" "https://m1.ppy.sh/r/osu!install.exe"

    WAYLAND_DISPLAY="" LC_ALL=en_US.UTF-8 "$WINE_BIN" "$WINE_PREFIX/osu!install.exe" &

    yad --title="osu! Setup" --text="<b>ACTION REQUIRED:</b>\n\n1. Install osu!\n2. Let it launch.\n3. <b>CLOSE osu!</b> to continue setup." \
        --button="Done:0" --center --width=400

    pkill -f "osu!install.exe" || true
    pkill -f "osu!.exe" || true
    TARGET_OSU_EXE=$(find "$WINE_PREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)
fi

if [ -z "$TARGET_OSU_EXE" ]; then notify_error "osu!.exe not found."; fi

# --- 8. Wrapper & Integration ---

# Icons
ICON_DIR="$HOME/.local/share/icons/hicolor/128x128/apps"
mkdir -p "$ICON_DIR"
if [ ! -f "$ICON_DIR/osu-stable-game.png" ]; then
    curl -L -o "$ICON_DIR/osu-stable-game.png" "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Osu%21_Logo_2016.svg/512px-Osu%21_Logo_2016.svg.png"
    curl -L -o "$ICON_DIR/osu-stable-map.png" "https://img.icons8.com/ios11/512/228BE6/osu-lazer.png"
    curl -L -o "$ICON_DIR/osu-stable-skin.png" "https://img.icons8.com/ios11/512/FAB005/osu-lazer.png"
    curl -L -o "$ICON_DIR/osu-stable-replay.png" "https://img.icons8.com/ios11/512/7950F2/osu-lazer.png"
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

# Wrapper
CONFIG_DIR="$HOME/.config/osu-importer"
WRAPPER="$CONFIG_DIR/osu_importer_wrapper.sh"
mkdir -p "$CONFIG_DIR"

WRAPPER_ENV="export LANG=en_US.UTF-8; export LC_ALL=en_US.UTF-8"
WRAPPER_ENV="$WRAPPER_ENV; export STAGING_AUDIO_DURATION=10000; export PULSE_LATENCY_MSEC=60"

if [[ "$DRIVER_SELECTION" == *"Wayland"* ]]; then
    WRAPPER_ENV="$WRAPPER_ENV; unset DISPLAY"
else
    WRAPPER_ENV="$WRAPPER_ENV; export WAYLAND_DISPLAY=''"
fi

cat > "$WRAPPER" << EOF
#!/bin/bash
WINE_PREFIX="$WINE_PREFIX"
WINE_BIN="$WINE_BIN"
OSU_LINUX="$TARGET_OSU_EXE"
WINEPATH_BIN="\${WINE_BIN%/*}/winepath"
if [ ! -x "\$WINEPATH_BIN" ]; then WINEPATH_BIN="winepath"; fi
WINE_USER=\$(ls -1 "\$WINE_PREFIX/drive_c/users/" | head -n 1)
TEMP_LINUX="\$WINE_PREFIX/drive_c/users/\$WINE_USER/Temp"
$WRAPPER_ENV

mkdir -p "\$TEMP_LINUX"
find "\$TEMP_LINUX" -type f -mmin +60 -delete 2>/dev/null || true

if ! pgrep -f "osu!.exe" > /dev/null; then
    notify-send "osu!" "Launching..."
    ( export WINEPREFIX="\$WINE_PREFIX"; "\$WINE_BIN" "\$OSU_LINUX" & )
    for i in {1..45}; do if pgrep -f "osu!.exe" > /dev/null; then sleep 5; break; fi; sleep 1; done
fi

for FILE in "\$@"; do
    if [ ! -f "\$FILE" ]; then continue; fi
    NAME="\$(basename "\$FILE")"
    cp "\$FILE" "\$TEMP_LINUX/\$NAME"
    WIN_PATH=\$(export WINEPREFIX="\$WINE_PREFIX"; "\$WINEPATH_BIN" -w "\$TEMP_LINUX/\$NAME" | tr -d '\r')
    export WINEPREFIX="\$WINE_PREFIX"
    if ! "\$WINE_BIN" "\$OSU_LINUX" "\$WIN_PATH" &>/dev/null; then
        notify-send -u critical "osu! Importer" "Failed: \$NAME"
    else
        if [[ "\$NAME" == *.osz ]]; then rm "\$FILE"; fi
        notify-send "osu! Importer" "Imported: \$NAME"
    fi
done
exit 0
EOF
chmod +x "$WRAPPER"

# Desktop Entry
cat > "$HOME/.local/share/applications/osu-stable.desktop" << EOF
[Desktop Entry]
Name=osu! (Stable)
Exec="$WRAPPER"
Icon=osu-stable-game
Type=Application
Categories=Game;
StartupWMClass=osu!.exe
EOF

# Mime Types
cat > "$HOME/.local/share/applications/osu-importer.desktop" << EOF
[Desktop Entry]
Name=osu! Importer
Exec="$WRAPPER" %F
Type=Application
Icon=osu-stable-game
MimeType=application/x-osu-beatmap;application/x-osu-skin;application/x-osu-replay;
NoDisplay=true
EOF

update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
xdg-mime default osu-importer.desktop application/x-osu-beatmap
xdg-mime default osu-importer.desktop application/x-osu-skin
xdg-mime default osu-importer.desktop application/x-osu-replay

notify_user "Installation Complete!\n\nLaunch osu! from your application menu."
exit 0
