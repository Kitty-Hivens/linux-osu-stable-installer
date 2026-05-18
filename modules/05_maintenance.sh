#!/bin/bash
# Module: Maintenance — Update, Uninstall, Health Check, Export/Import Config

# ==============================================================================
# UPDATE MODE
# Re-applies graphics, fonts, RPC, and integration without touching the prefix
# or re-downloading osu!. Reads settings from existing config or CLI flags.
# ==============================================================================

run_update() {
    # init_config has already restored the prior selections via load_installer_state
    # and resolved WINE_BIN — we just need to make sure TARGET_OSU_EXE is set.
    if [ -z "${TARGET_OSU_EXE:-}" ] || [ ! -f "${TARGET_OSU_EXE:-/nonexistent}" ]; then
        notify_error "Cannot locate osu!.exe for update. Run a fresh install first."
    fi

    log_info "Update Mode: re-applying settings to existing installation."

    configure_graphics
    install_fonts

    if [ "$INSTALL_RPC_BOOL" = "TRUE" ]; then
        install_discord_rpc
    fi

    create_system_integration
    create_osu_symlinks

    log_info "Update complete."
    notify_user "Update complete!\n\nSettings re-applied. Launch osu! from your app menu."
}

# ==============================================================================
# UNINSTALL
# ==============================================================================

run_uninstall() {
    log_info "Starting uninstallation..."

    local CONFIG_FILE="$HOME/.config/osu-importer/osu-env.conf"
    local PREFIX="$HOME/.wine-osu"  # fallback default

    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        PREFIX="${WINE_PREFIX:-$PREFIX}"
    fi

    if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
        yad --title="Uninstall osu!" \
            --text="<b>This will permanently remove:</b>\n\n• Wine prefix: <tt>$PREFIX</tt>\n• Desktop entries\n• MIME types\n• Wrapper config\n• Convenience symlinks (<tt>~/osu/</tt>)\n\n<b>Your beatmaps and skins inside the prefix will be deleted.</b>\nBack them up first if needed." \
            --button="Cancel:1" --button="Uninstall:0" --center --width=480

        if [ $? -ne 0 ]; then
            log_info "Uninstall cancelled by user."
            exit 0
        fi
    else
        echo ""
        echo "[WARNING] This will permanently delete the osu! Wine prefix and all integration files."
        echo "Prefix: $PREFIX"
        read -rp "Type 'yes' to confirm: " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo "Uninstall cancelled."
            exit 0
        fi
    fi

    log_info "Killing running osu! processes..."
    pkill -f "osu!.exe"    2>/dev/null || true
    pkill -f "osu!install" 2>/dev/null || true

    log_info "Removing Wine prefix: $PREFIX"
    rm -rf "$PREFIX"

    log_info "Removing desktop entries..."
    rm -f "$HOME/.local/share/applications/osu-stable.desktop"
    rm -f "$HOME/.local/share/applications/osu-importer.desktop"

    log_info "Removing MIME types..."
    rm -f "$HOME/.local/share/mime/packages/osu-file-types.xml"
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true

    log_info "Removing icons..."
    rm -f "$HOME/.local/share/icons/hicolor/128x128/apps/osu-stable"*.png
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

    log_info "Removing config and wrapper..."
    rm -rf "$HOME/.config/osu-importer"

    log_info "Removing symlinks..."
    local LINKS_TARGET="${LINKS_DIR:-$HOME/osu}"
    for dir in Songs Skins Logs Chat; do
        [ -L "$LINKS_TARGET/$dir" ] && rm "$LINKS_TARGET/$dir" && log_info "  Removed symlink: $LINKS_TARGET/$dir"
    done
    # Remove the symlinks dir itself only if it's now empty
    if [ -d "$LINKS_TARGET" ] && [ -z "$(ls -A "$LINKS_TARGET" 2>/dev/null)" ]; then
        rmdir "$LINKS_TARGET"
        log_info "  Removed empty symlink directory: $LINKS_TARGET"
    fi

    log_info "Removing installer log..."
    rm -f "$HOME/.osu_installer.log"

    log_info "Uninstallation complete."
    if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
        yad --title="Uninstall Complete" \
            --text="osu! has been fully removed from your system." \
            --image="dialog-information" --button="OK:0" --center --width=350 || true
    else
        echo "[SUCCESS] osu! has been fully removed."
    fi
}

# ==============================================================================
# HEALTH CHECK
# Verifies installation integrity without modifying anything
# ==============================================================================

run_health_check() {
    log_info "Running Health Check..."

    local CONFIG_FILE="$HOME/.config/osu-importer/osu-env.conf"
    local PASS=0
    local FAIL=0
    local REPORT=""

    _check() {
        local LABEL="$1"
        local STATUS="$2"  # "ok" or "fail"
        local DETAIL="$3"
        if [ "$STATUS" = "ok" ]; then
            PASS=$((PASS + 1))
            REPORT="$REPORT✅ $LABEL\n"
        else
            FAIL=$((FAIL + 1))
            REPORT="$REPORT❌ $LABEL — $DETAIL\n"
        fi
    }

    # Load config if it exists
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        _check "Config file" "ok" ""
    else
        _check "Config file" "fail" "Not found at $CONFIG_FILE"
    fi

    # Wine binary
    if [ -n "$WINE_BIN" ] && command -v "$WINE_BIN" &> /dev/null; then
        local WINE_VER
        WINE_VER=$("$WINE_BIN" --version 2>/dev/null || echo "unknown")
        _check "Wine binary ($WINE_VER)" "ok" ""
    else
        _check "Wine binary" "fail" "Not found: ${WINE_BIN:-unset}"
    fi

    # Wine prefix
    if [ -d "${WINE_PREFIX:-}" ]; then
        _check "Wine prefix" "ok" ""
    else
        _check "Wine prefix" "fail" "Directory not found: ${WINE_PREFIX:-unset}"
    fi

    # osu!.exe
    if [ -n "${OSU_LINUX:-}" ] && [ -f "$OSU_LINUX" ]; then
        _check "osu!.exe" "ok" ""
    else
        _check "osu!.exe" "fail" "Not found: ${OSU_LINUX:-unset}"
    fi

    # Wrapper script
    local WRAPPER="$HOME/.config/osu-importer/osu_importer_wrapper.sh"
    if [ -x "$WRAPPER" ]; then
        _check "Wrapper script" "ok" ""
    else
        _check "Wrapper script" "fail" "Not found or not executable: $WRAPPER"
    fi

    # Desktop entries
    if [ -f "$HOME/.local/share/applications/osu-stable.desktop" ]; then
        _check "Desktop entry (launcher)" "ok" ""
    else
        _check "Desktop entry (launcher)" "fail" "Missing osu-stable.desktop"
    fi

    if [ -f "$HOME/.local/share/applications/osu-importer.desktop" ]; then
        _check "Desktop entry (importer)" "ok" ""
    else
        _check "Desktop entry (importer)" "fail" "Missing osu-importer.desktop"
    fi

    # MIME types
    if [ -f "$HOME/.local/share/mime/packages/osu-file-types.xml" ]; then
        _check "MIME type definitions" "ok" ""
    else
        _check "MIME type definitions" "fail" "Missing osu-file-types.xml"
    fi

    # Symlinks
    local LINKS_TARGET="${LINKS_DIR:-$HOME/osu}"
    local SYMLINKS_OK=true
    for dir in Songs Skins Logs Chat; do
        if [ ! -L "$LINKS_TARGET/$dir" ]; then
            SYMLINKS_OK=false
            break
        fi
    done
    if [ "$SYMLINKS_OK" = true ]; then
        _check "Convenience symlinks ($LINKS_TARGET)" "ok" ""
    else
        _check "Convenience symlinks ($LINKS_TARGET)" "fail" "One or more symlinks missing. Run --update to recreate."
    fi

    # winetricks
    if command -v winetricks &> /dev/null; then
        _check "winetricks" "ok" ""
    else
        _check "winetricks" "fail" "Not found in PATH"
    fi

    # Summary
    local SUMMARY="Health Check Results: $PASS passed, $FAIL failed\n\n$REPORT"
    log_info "Health check: $PASS passed, $FAIL failed"

    if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
        local ICON_TYPE="dialog-information"
        [ $FAIL -gt 0 ] && ICON_TYPE="dialog-warning"
        yad --title="osu! Health Check" \
            --text="$SUMMARY" \
            --image="$ICON_TYPE" \
            --button="OK:0" --center --width=500 || true
    else
        echo -e "\n$SUMMARY"
    fi

    [ $FAIL -eq 0 ]  # exit code 0 if all passed, 1 if any failed
}

# ==============================================================================
# EXPORT CONFIG
# ==============================================================================

export_config() {
    local BACKUP_FILE="$HOME/osu-config-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
    local CONFIG_DIR="$HOME/.config/osu-importer"

    log_info "Exporting config to $BACKUP_FILE..."

    if [ ! -d "$CONFIG_DIR" ]; then
        notify_error "No config directory found at $CONFIG_DIR. Is osu! installed?"
    fi

    # Only include files that actually exist; tar would otherwise abort on the first missing path.
    local TAR_ARGS=(".config/osu-importer")
    [ -f "$HOME/.local/share/applications/osu-stable.desktop" ]   && TAR_ARGS+=(".local/share/applications/osu-stable.desktop")
    [ -f "$HOME/.local/share/applications/osu-importer.desktop" ] && TAR_ARGS+=(".local/share/applications/osu-importer.desktop")
    [ -f "$HOME/.local/share/mime/packages/osu-file-types.xml" ]  && TAR_ARGS+=(".local/share/mime/packages/osu-file-types.xml")

    if ! tar -czf "$BACKUP_FILE" -C "$HOME" "${TAR_ARGS[@]}" 2>>"$LOG_FILE"; then
        rm -f "$BACKUP_FILE"
        notify_error "tar failed while creating $BACKUP_FILE. See $LOG_FILE for details."
    fi

    if [ ! -s "$BACKUP_FILE" ]; then
        rm -f "$BACKUP_FILE"
        notify_error "Backup archive is empty or missing: $BACKUP_FILE"
    fi

    log_info "Config exported to: $BACKUP_FILE"

    if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
        notify_user "Config exported successfully!\n\nBackup saved to:\n<tt>$BACKUP_FILE</tt>"
    else
        echo "[SUCCESS] Config exported to: $BACKUP_FILE"
    fi
}

# ==============================================================================
# IMPORT CONFIG
# ==============================================================================

import_config() {
    local BACKUP_FILE="$1"

    if [ -z "$BACKUP_FILE" ]; then
        if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
            BACKUP_FILE=$(yad --file-selection \
                --title="Select osu! config backup" \
                --file-filter="Backup archives | *.tar.gz")
            [ -z "$BACKUP_FILE" ] && exit 0
        else
            notify_error "Usage: ./install.sh --import-config <path/to/backup.tar.gz>"
        fi
    fi

    if [ ! -f "$BACKUP_FILE" ]; then
        notify_error "Backup file not found: $BACKUP_FILE"
    fi

    log_info "Importing config from $BACKUP_FILE..."

    tar -xzf "$BACKUP_FILE" -C "$HOME" || notify_error "Failed to extract backup archive."

    # Refresh desktop integration caches so the restored .desktop/MIME entries take effect now,
    # not after the next login.
    update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

    log_info "Config imported successfully."

    if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
        notify_user "Config imported successfully!\n\nRestart osu! for changes to take effect."
    else
        echo "[SUCCESS] Config imported from: $BACKUP_FILE"
    fi
}

# ==============================================================================
# LAUNCH
# Launches osu! directly via the saved config, bypassing the installer.
# Useful for debugging — Wine output goes straight to the terminal.
# ==============================================================================

launch_osu() {
    local CONFIG_FILE="$HOME/.config/osu-importer/osu-env.conf"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[ERROR] Config not found at $CONFIG_FILE"
        echo "        Run the installer first, or use --import-config to restore a backup."
        exit 1
    fi

    source "$CONFIG_FILE"

    # Validate required vars are present
    local MISSING=""
    [ -z "${WINE_BIN:-}"    ] && MISSING="$MISSING WINE_BIN"
    [ -z "${WINE_PREFIX:-}" ] && MISSING="$MISSING WINE_PREFIX"
    [ -z "${OSU_LINUX:-}"   ] && MISSING="$MISSING OSU_LINUX"

    if [ -n "$MISSING" ]; then
        echo "[ERROR] Config is incomplete. Missing:$MISSING"
        echo "        Run --health-check for details."
        exit 1
    fi

    if [ ! -f "$OSU_LINUX" ]; then
        echo "[ERROR] osu!.exe not found at: $OSU_LINUX"
        echo "        The prefix may have been moved or deleted."
        exit 1
    fi

    local WINE_VER
    WINE_VER=$("$WINE_BIN" --version 2>/dev/null || echo "version unknown")

    echo "[INFO] Launching osu! (debug mode)"
    echo "[INFO]   Wine:   $WINE_BIN ($WINE_VER)"
    echo "[INFO]   Prefix: $WINE_PREFIX"
    echo "[INFO]   Exe:    $OSU_LINUX"
    echo "[INFO] Wine output below — Ctrl+C to kill"
    echo "------------------------------------------------------------"

    # exec replaces the shell process — clean, no dangling parent
    export WINEPREFIX="$WINE_PREFIX"
    exec "$WINE_BIN" "$OSU_LINUX"
}
