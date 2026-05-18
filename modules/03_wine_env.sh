#!/bin/bash
# Module: Wine Prefix, Graphics APIs, and Fonts

setup_wine_prefix() {
    log_info "Setting up Wine Prefix at $WINE_PREFIX..."
    mkdir -p "$WINE_PREFIX"

    if [[ "$DOTNET_SELECTION" == *"Mono"* ]]; then
        log_info "Using Wine Mono — skipping MS .NET 4.8 installation."
        env WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" wineboot -u 2>/dev/null || true
    else
        if [ ! -d "$WINE_PREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319" ]; then
            log_info "Installing MS .NET 4.8 Framework (this may take several minutes)..."
            local INSTALL_CMD="WINEPREFIX=\"$WINE_PREFIX\" WAYLAND_DISPLAY=\"\" winetricks -q dotnet48"
            if [ "$SILENT_MODE" = false ]; then
                ( set +e; eval "$INSTALL_CMD"; set -e ) 2>&1 | yad --progress --pulsate --auto-close --no-cancel \
                    --title="Installing .NET" --text="Installing MS .NET 4.8 Framework...\nThis takes several minutes." \
                    --center --width=400
            else
                set +e; eval "$INSTALL_CMD"; set -e
            fi
        else
            log_info ".NET 4.8 already installed — skipping."
        fi
    fi
}

configure_graphics() {
    log_info "Configuring Graphics Stack: $RENDERER_SELECTION / $DRIVER_SELECTION"

    local GRAPHICS_SCRIPT=$(cat << 'EOF'
        if [[ "$RENDERER_SELECTION" == *"DXVK"* ]]; then
            echo "Installing DXVK..."
            WINEPREFIX="$WINE_PREFIX" winetricks -q dxvk
        else
            echo "Reverting to OpenGL (removing DXVK overrides)..."
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d9"  /f 2>/dev/null || true
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "dxgi"  /f 2>/dev/null || true
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d11" /f 2>/dev/null || true
        fi

        # Modern Wine (11.3+) uses WINEWAYLAND=1 env var — remove old registry key to avoid conflicts
        WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\Drivers" /v "Graphics" /f 2>/dev/null || true
EOF
)

    if [ "$SILENT_MODE" = false ]; then
        ( eval "$GRAPHICS_SCRIPT" ) 2>&1 | yad --progress --pulsate --auto-close \
            --title="Graphics" --text="Applying graphics settings..." --center
    else
        eval "$GRAPHICS_SCRIPT"
    fi
}

install_fonts() {
    # FIX: Check Skip BEFORE touching the Fonts directory
    if [[ "$FONT_SELECTION" == "Skip" ]]; then
        log_info "Skipping font installation."
        return
    fi

    log_info "Installing fonts: $FONT_SELECTION"

    local FONT_DIR="$WINE_PREFIX/drive_c/windows/Fonts"
    mkdir -p "$FONT_DIR"
    # Remove only fonts this installer might have placed previously, and any
    # stale symlinks from a prior "System Links" run — never user-owned files.
    rm -f "$FONT_DIR/wqy-microhei.ttc" \
          "$FONT_DIR/osu-font.otf" \
          "$FONT_DIR/Koruri-Regular.ttf" \
          "$FONT_DIR/koruri.tar.xz"
    find "$FONT_DIR" -maxdepth 1 -type l -delete 2>/dev/null || true

    local FONTS_SCRIPT=$(cat << 'EOF'
        FONT_READY=false
        case "$FONT_SELECTION" in
          "WenQuanYi"*)
            echo "Downloading WenQuanYi Micro Hei..."
            if download \
                "https://github.com/anthonyfok/fonts-wqy-microhei/raw/master/wqy-microhei.ttc" \
                "$FONT_DIR/wqy-microhei.ttc"; then
                cat > "$WINE_PREFIX/font_fix.reg" << REGEOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="WenQuanYi Micro Hei"
"Segoe UI"="WenQuanYi Micro Hei"
"MS Gothic"="WenQuanYi Micro Hei"
"Meiryo"="WenQuanYi Micro Hei"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"WenQuanYi Micro Hei (TrueType)"="wqy-microhei.ttc"
REGEOF
                FONT_READY=true
            else
                echo "[WARN] Skipping WenQuanYi — download failed."
            fi
            ;;
          "Noto Sans"*)
            echo "Downloading Noto Sans CJK JP..."
            if download \
                "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf" \
                "$FONT_DIR/osu-font.otf"; then
                cat > "$WINE_PREFIX/font_fix.reg" << REGEOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="Noto Sans CJK JP Regular"
"Segoe UI"="Noto Sans CJK JP Regular"
"MS Gothic"="Noto Sans CJK JP Regular"
"Meiryo"="Noto Sans CJK JP Regular"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"Noto Sans CJK JP Regular (TrueType)"="osu-font.otf"
REGEOF
                FONT_READY=true
            else
                echo "[WARN] Skipping Noto Sans CJK — download failed."
            fi
            ;;
          "Koruri"*)
            echo "Downloading Koruri..."
            cd "$FONT_DIR"
            if download \
                "https://github.com/Koruri/Koruri/releases/download/20210720/Koruri-20210720.tar.xz" \
                "$FONT_DIR/koruri.tar.xz" \
                && tar -xf koruri.tar.xz; then
                find . -name "Koruri-Regular.ttf" -exec mv {} . \;
                rm -rf Koruri-* koruri.tar.xz
                cat > "$WINE_PREFIX/font_fix.reg" << REGEOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="Koruri Regular"
"Segoe UI"="Koruri Regular"
"MS Gothic"="Koruri Regular"
"Meiryo"="Koruri Regular"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"Koruri Regular (TrueType)"="Koruri-Regular.ttf"
REGEOF
                FONT_READY=true
            else
                echo "[WARN] Skipping Koruri — download or extraction failed."
                rm -f koruri.tar.xz
            fi
            ;;
          "System"*)
            echo "Linking System Fonts..."
            find /usr/share/fonts -type f \( -name "*.ttf" -o -name "*.otf" \) \
                -exec ln -sf {} "$FONT_DIR" \; 2>/dev/null || true
            find "$HOME/.local/share/fonts" -type f \( -name "*.ttf" -o -name "*.otf" \) \
                -exec ln -sf {} "$FONT_DIR" \; 2>/dev/null || true
            echo "REGEDIT4" > "$WINE_PREFIX/font_fix.reg"
            FONT_READY=true
            ;;
        esac

        if [ "$FONT_READY" = true ]; then
            # Global Font Smoothing (ClearType equivalents)
            cat >> "$WINE_PREFIX/font_fix.reg" << REGEOF
[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001
"FontSmoothingType"=dword:00000002
[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Nls\CodePage]
"932"="cp932.nls"
"00000411"="cp932.nls"
REGEOF
            WINEPREFIX="$WINE_PREFIX" WAYLAND_DISPLAY="" "$WINE_BIN" regedit "$WINE_PREFIX/font_fix.reg" 2>/dev/null || true
            rm -f "$WINE_PREFIX/font_fix.reg"
        fi
EOF
)

    if [ "$SILENT_MODE" = false ]; then
        ( eval "$FONTS_SCRIPT" ) 2>&1 | yad --progress --pulsate --auto-close --no-cancel \
            --title="Fonts" --text="Installing CJK fonts..." --center
    else
        eval "$FONTS_SCRIPT"
    fi
}
