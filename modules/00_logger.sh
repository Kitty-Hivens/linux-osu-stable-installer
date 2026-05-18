#!/bin/bash
# Module: Logger & Utils

LOG_FILE="$HOME/.osu_installer.log"
LOG_MAX_BYTES=1048576  # 1 MiB

# Rotate if the log has grown beyond the threshold so it does not accumulate forever
if [ -f "$LOG_FILE" ]; then
    _log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "${_log_size:-0}" -gt "$LOG_MAX_BYTES" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
    unset _log_size
fi

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

# Download $1 to $2 with --fail. Returns 0 on success and non-empty file.
# On failure: removes any partial file and logs an error. Caller decides whether to abort.
download() {
    local url="$1"
    local out="$2"
    if curl -L --fail -sS -o "$out" "$url" && [ -s "$out" ]; then
        return 0
    fi
    log_error "Download failed or empty: $url"
    rm -f "$out"
    return 1
}
