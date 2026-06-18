#!/bin/bash
# Module: Wine Prefix, Graphics APIs, and Fonts

setup_wine_prefix() {
    log_info "Setting up Wine Prefix at $WINE_PREFIX..."
    mkdir -p "$WINE_PREFIX"

    if [[ "$DOTNET_SELECTION" == *"Mono"* ]]; then
        log_info "Using Wine Mono — skipping MS .NET 4.8 installation."
        env WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" wineboot -u &>/dev/null || true
    else
        if [ ! -d "$WINE_PREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319" ]; then
            log_info "Installing MS .NET 4.8 Framework (this may take several minutes)..."
            local INSTALL_CMD="WINEPREFIX=\"$WINE_PREFIX\" WAYLAND_DISPLAY=\"\" winetricks -q dotnet48"
            command -v gum &> /dev/null && gum style --foreground 212 "Installing MS .NET 4.8 Framework (several minutes)..." || true
            set +e; eval "$INSTALL_CMD"; set -e
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
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d9"  /f &>/dev/null || true
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "dxgi"  /f &>/dev/null || true
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d11" /f &>/dev/null || true
        fi

        # The registry "Graphics" key is the real driver selector. WINEWAYLAND=1 alone
        # is a no-op -- it does NOT switch the driver. Set the key to match the choice.
        if [[ "$DRIVER_SELECTION" == *"Wayland"* ]]; then
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /v "Graphics" /d "wayland,x11" /f &>/dev/null || true
        else
            WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /v "Graphics" /d "x11" /f &>/dev/null || true
        fi
EOF
)

    command -v gum &> /dev/null && gum style --foreground 212 "Applying graphics settings..." || true
    eval "$GRAPHICS_SCRIPT"
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
            WINEPREFIX="$WINE_PREFIX" WAYLAND_DISPLAY="" "$WINE_BIN" regedit "$WINE_PREFIX/font_fix.reg" &>/dev/null || true
            rm -f "$WINE_PREFIX/font_fix.reg"
        fi
EOF
)

    command -v gum &> /dev/null && gum style --foreground 212 "Installing CJK fonts..." || true
    eval "$FONTS_SCRIPT"

    # Symbol fallback: osu! honors GDI SystemLink, so chain the title fonts to a symbol
    # font for glyphs the chosen CJK font lacks -- e.g. dingbats like U+2727 (the decorative
    # stars in beatmap titles) that NO CJK font carries; without this they render as boxes.
    local SYM_DIR="$WINE_PREFIX/drive_c/windows/Fonts"
    mkdir -p "$SYM_DIR"
    local _deja _sym _linked=()
    _deja=$(fc-list ':charset=2727' file 2>/dev/null | grep -iE '/DejaVuSans\.ttf' | head -1 | sed 's/: *$//;s/:$//')
    _sym=$(fc-list ':charset=2727' file 2>/dev/null | grep -iE 'NotoSansSymbols2-Regular\.ttf' | head -1 | sed 's/: *$//;s/:$//')
    [ -n "$_deja" ] && { ln -sf "$_deja" "$SYM_DIR/DejaVuSans.ttf";            _linked+=("DejaVuSans.ttf,DejaVu Sans"); }
    [ -n "$_sym"  ] && { ln -sf "$_sym"  "$SYM_DIR/NotoSansSymbols2-Regular.ttf"; _linked+=("NotoSansSymbols2-Regular.ttf,Noto Sans Symbols 2"); }

    if [ ${#_linked[@]} -gt 0 ]; then
        local _data="" _e _base
        for _e in "${_linked[@]}"; do _data="${_data:+$_data\\0}$_e"; done
        for _base in "Tahoma" "Arial" "Segoe UI" "MS UI Gothic" "Aller" "Aller Light" \
                     "Noto Sans CJK JP Regular" "WenQuanYi Micro Hei" "Koruri Regular"; do
            WINEPREFIX="$WINE_PREFIX" WAYLAND_DISPLAY="" "$WINE_BIN" reg add \
                "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink" \
                /v "$_base" /t REG_MULTI_SZ /d "$_data" /f &>/dev/null || true
        done
        log_info "Symbol-glyph fallback (SystemLink) configured -- decorative dingbats render instead of boxes."
    else
        log_warn "No symbol font (DejaVu Sans / Noto Sans Symbols 2) found; decorative glyphs may show as boxes."
    fi
}
