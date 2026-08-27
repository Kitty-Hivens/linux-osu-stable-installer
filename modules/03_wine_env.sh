#!/bin/bash
# Module: Wine Prefix, Graphics APIs, and Fonts

# Drop file-indexer opt-out markers at the prefix root so background indexers skip the whole
# Wine tree -- above all the large Songs directory, which otherwise wastes IO/CPU on every scan.
# .trackerignore is read by GNOME Tracker (tracker-miners); .nomedia is honored by Tracker and
# several other indexers. Idempotent: existing markers are left untouched.
write_index_markers() {
    [ -d "$WINE_PREFIX" ] || return 0
    local marker
    for marker in .trackerignore .nomedia; do
        [ -e "$WINE_PREFIX/$marker" ] || : > "$WINE_PREFIX/$marker"
    done
}

# ==============================================================================
# Wine version guard: keep a known-broken Wine away from the beatmap database
# ==============================================================================

# Version the package manager would install for package $1, asked before anything is
# installed so a broken release can be refused instead of diagnosed afterwards.
# Empty when the package manager is unknown or carries no such package.
_pm_candidate_version() {
    local pkg="$1" out=""
    if command -v pacman &> /dev/null; then
        out=$(pacman -Si "$pkg" 2>/dev/null | awk -F': *' '/^Version/{print $2; exit}')
    elif command -v apt-cache &> /dev/null; then
        out=$(apt-cache policy "$pkg" 2>/dev/null | awk -F': *' '/Candidate:/{print $2; exit}')
    elif command -v dnf &> /dev/null; then
        out=$(dnf -q info "$pkg" 2>/dev/null | awk -F': *' '/^Version/{print $2; exit}')
    elif command -v xbps-query &> /dev/null; then
        out=$(xbps-query -R -p pkgver "$pkg" 2>/dev/null)
    fi
    wine_version_number "$out"
}

# Newest cached package of $1 whose version is not on the broken list; echoes its path.
# Only pacman's cache is searched. Its layout and file naming are stable enough to read a
# version straight off the filename, which is what makes an offline downgrade possible at
# all; elsewhere the guard falls back to telling the user what to do by hand.
_cached_good_wine_pkg() {
    local pkg="$1" f ver best="" best_ver=""
    command -v pacman &> /dev/null || return 1
    for f in /var/cache/pacman/pkg/"$pkg"-[0-9]*.pkg.tar.*; do
        case "$f" in *.sig) continue ;; esac
        [ -f "$f" ] || continue
        ver=$(wine_version_number "$(basename "$f")")
        [ -n "$ver" ] || continue
        wine_version_is_broken "$ver" && continue
        if [ -z "$best_ver" ] || [ "$(printf '%s\n%s\n' "$best_ver" "$ver" | sort -V | tail -n1)" = "$ver" ]; then
            best_ver="$ver"
            best="$f"
        fi
    done
    [ -n "$best" ] || return 1
    printf '%s' "$best"
}

# Unpack package file $1 (version $2) into ~/.local/opt/wine-$2 and echo the wine binary
# inside it. A Wine tree is relocatable -- the loader finds its own lib directory relative
# to the binary -- so this needs no root and leaves the system package untouched.
_pin_wine_from_pkg() {
    local pkg_file="$1" ver="$2" dest="$HOME/.local/opt/wine-$2"
    command -v bsdtar &> /dev/null || return 1
    rm -rf "$dest"
    mkdir -p "$dest" || return 1
    if ! bsdtar -xf "$pkg_file" -C "$dest" 2>/dev/null; then
        rm -rf "$dest"
        return 1
    fi
    rm -f "$dest/.PKGINFO" "$dest/.MTREE" "$dest/.INSTALL" "$dest/.BUILDINFO"
    [ -x "$dest/usr/bin/wine" ] || { rm -rf "$dest"; return 1; }
    printf '%s' "$dest/usr/bin/wine"
}

# Which package name to look for in the cache. WINE_SELECTION is the package label the
# user picked ("wine" / "wine-staging"); an absolute path was pinned already and is left
# alone. Arch ships no `wine-staging` binary, so the label is the only thing that says
# which package the installed `wine` actually came from.
_wine_package_name() {
    case "$WINE_SELECTION" in
        /*) printf '%s' "" ;;
        *)  printf '%s' "$WINE_SELECTION" ;;
    esac
}

# Offer the system-wide downgrade. Kept separate because it is the invasive branch: it
# needs root, it changes Wine for everything else on the machine, and the very next
# `pacman -Syu` puts the broken version straight back unless it is held.
_offer_system_downgrade() {
    local pkg_file="$1" ver="$2" pkg="$3"
    local ELEVATE="pkexec"
    container_active && ELEVATE="sudo"

    log_info "Downgrading the system package to $ver ..."
    if ! $ELEVATE pacman -U "$pkg_file" --noconfirm; then
        notify_warning "The downgrade did not go through. Nothing was changed.
Run it by hand if you want to retry:
    sudo pacman -U $pkg_file"
        return 1
    fi

    # pacman.conf belongs to the user, not to this installer -- silently editing what the
    # system upgrades is exactly the kind of surprise a game installer has no business
    # springing. The line is printed instead, so holding the package stays a deliberate act.
    notify_user "Wine downgraded to $ver.

The next 'pacman -Syu' will pull the broken version back in. To hold it, add this to the
[options] section of /etc/pacman.conf yourself:

    IgnorePkg = $pkg

Remove that line once a fixed Wine is released."
    return 0
}

# The guard proper. Determines which Wine version is about to be used -- the installed
# binary, or the one the package manager is about to fetch -- and refuses to walk into a
# release known to destroy the beatmap database without saying so first.
#
# On acceptance the replacement goes into WINE_SELECTION rather than WINE_BIN: an absolute
# path travels through resolve_wine_bin verbatim and is stored as INSTALLER_WINE_SELECTION,
# so the pin survives a later --update, which regenerates osu-env.conf from scratch.
wine_version_guard() {
    local ver pkg pkg_file good_ver pinned choice

    pkg=$(_wine_package_name)
    if [ -z "$pkg" ]; then
        # An explicit path is the user's own choice; still say so if it is a broken build.
        ver=$(wine_binary_version "$WINE_BIN")
        wine_version_is_broken "$ver" || return 0
        notify_warning "The Wine you pointed the installer at is $ver.

$(wine_broken_blurb)"
        return 0
    fi

    ver=$(wine_binary_version "$WINE_BIN")
    [ -n "$ver" ] || ver=$(_pm_candidate_version "$pkg")
    wine_version_is_broken "$ver" || return 0

    log_warn "Wine $ver is on the known-broken list."

    pkg_file=$(_cached_good_wine_pkg "$pkg" || true)
    [ -n "$pkg_file" ] && good_ver=$(wine_version_number "$(basename "$pkg_file")")

    local HEAD="Wine $ver breaks osu!.

$(wine_broken_blurb)"

    # Unattended runs must not stop to ask, but must not hide it either.
    if [ "${SILENT_MODE:-false}" = true ]; then
        notify_warning "$HEAD

Continuing on Wine $ver because this is a silent run. Re-run without --silent to pick an
older Wine, or pass --wine /path/to/older/wine."
        return 0
    fi

    if [ -z "$pkg_file" ]; then
        notify_warning "$HEAD

No older Wine package was found in the local package cache, so the installer cannot put
one in place for you. Install an older Wine yourself and point the installer at it:

    ./install.sh --wine /path/to/older/wine

Known good: any release before $WINE_BROKEN_VERSIONS."
        return 0
    fi

    notify_warning "$HEAD

Wine $good_ver is sitting in the local package cache, and it reads the database fine."

    if command -v gum &> /dev/null; then
        choice=$(gum choose --header "How should the installer handle Wine $ver?" \
            "Use Wine $good_ver alongside the system one (no root, nothing else changes)" \
            "Downgrade the system package to $good_ver (needs root, affects everything)" \
            "Continue on Wine $ver anyway") || choice=""
    else
        echo ""
        echo "  1) Use Wine $good_ver alongside the system one (no root, nothing else changes)"
        echo "  2) Downgrade the system package to $good_ver (needs root, affects everything)"
        echo "  3) Continue on Wine $ver anyway"
        read -rp "Choice [1]: " choice
        case "${choice:-1}" in
            1) choice="Use Wine" ;;
            2) choice="Downgrade the system" ;;
            *) choice="Continue" ;;
        esac
    fi

    case "$choice" in
        "Use Wine"*)
            log_info "Unpacking Wine $good_ver to ~/.local/opt ..."
            pinned=$(_pin_wine_from_pkg "$pkg_file" "$good_ver" || true)
            if [ -z "$pinned" ]; then
                notify_warning "Could not unpack $pkg_file.
Continuing on Wine $ver -- the beatmap database will not survive a launch."
                return 0
            fi
            WINE_SELECTION="$pinned"
            WINE_BIN="$pinned"
            export WINE="$WINE_BIN"
            notify_user "osu! now runs on Wine $good_ver from:
    $pinned

The system Wine stays at $ver and keeps updating normally -- only osu! is pinned. The pin
is stored with the rest of your settings, so --update keeps it. To undo it later, re-run
the installer and pick the plain '$pkg' entry."
            ;;
        "Downgrade the system"*)
            if _offer_system_downgrade "$pkg_file" "$good_ver" "$pkg"; then
                WINE_BIN=$(resolve_wine_bin "$WINE_SELECTION")
                export WINE="$WINE_BIN"
            fi
            ;;
        *)
            notify_warning "Continuing on Wine $ver.
Back up $WINE_PREFIX/drive_c/users/*/AppData/Local/osu!/osu!.db before launching."
            ;;
    esac
}

setup_wine_prefix() {
    log_info "Setting up Wine Prefix at $WINE_PREFIX..."
    mkdir -p "$WINE_PREFIX"
    write_index_markers

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
