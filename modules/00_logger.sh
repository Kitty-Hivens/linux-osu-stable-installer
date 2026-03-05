#!/bin/bash
# Module: Logger & Utils

LOG_FILE="$HOME/.osu_installer.log"

# Initialize log file
echo "--- osu! Installer Run: $(date) ---" >> "$LOG_FILE"

log_info() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $1" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    echo "[WARNING] $1" | tee -a "$LOG_FILE"
}

# GUI Helpers (Fallback to console in silent mode)
SCRIPT_TITLE="osu! Installer v4.2"
ICON="applications-games"

notify_user() {
    if [ "$SILENT_MODE" = true ]; then
        log_info "$1"
    else
        yad --title="$SCRIPT_TITLE" --text="$1" --image="$ICON" --button="OK:0" --center --width=350 || true
    fi
}

notify_error() {
    log_error "$1"
    if [ "$SILENT_MODE" = false ] && command -v yad &> /dev/null; then
        yad --title="Error" --text="$1" --image="dialog-error" --button="Exit:1" --center --width=350 || true
    fi
    exit 1
}

notify_warning() {
    log_warn "$1"
    if [ "$SILENT_MODE" = false ]; then
        yad --title="Warning" --text="$1" --image="dialog-warning" --button="OK:0" --center --width=350 || true
    fi
}
