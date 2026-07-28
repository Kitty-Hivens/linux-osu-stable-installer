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

# Notification helpers: gum box when interactive, log fallback in silent mode.

notify_user() {
    if [ "${SILENT_MODE:-false}" = false ] && command -v gum &> /dev/null; then
        gum style --border rounded --padding "0 2" --border-foreground 212 "$(printf '%b' "$1")"
    else
        log_info "$1"
    fi
}

notify_error() {
    log_error "$1"
    if [ "${SILENT_MODE:-false}" = false ] && command -v gum &> /dev/null; then
        gum style --border rounded --padding "0 2" --border-foreground 196 "ERROR" "$(printf '%b' "$1")" || true
    fi
    exit 1
}

notify_warning() {
    log_warn "$1"
    if [ "${SILENT_MODE:-false}" = false ] && command -v gum &> /dev/null; then
        gum style --border rounded --padding "0 2" --border-foreground 214 "WARNING" "$(printf '%b' "$1")" || true
    fi
}

# wine and wine-staging both provide the `wine` binary on most distros (Arch ships no
# `wine-staging` binary at all); only a custom path is used verbatim. Maps the user's
# SELECTION to the real binary.
resolve_wine_bin() {
    case "$1" in
        /*)                echo "$1" ;;
        wine|wine-staging) command -v wine 2>/dev/null || echo wine ;;
        *)                 command -v "$1" 2>/dev/null || echo "$1" ;;
    esac
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

# True if $1 starts with the PNG signature. An HTTP 200 carrying an error page or an
# SVG passes download()'s non-empty check, and the resulting file would silently fail
# to render as an icon.
is_png() {
    [ -s "$1" ] || return 1
    [ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" = "89504e47" ]
}

# Echo the pixel dimensions of PNG $1 as WxH, read from the IHDR header.
png_size() {
    local w h
    w=$(od -An -tu4 -j16 -N4 --endian=big "$1" 2>/dev/null | tr -d ' ')
    h=$(od -An -tu4 -j20 -N4 --endian=big "$1" 2>/dev/null | tr -d ' ')
    [ -n "$w" ] && [ -n "$h" ] && [ "$w" -gt 0 ] && [ "$h" -gt 0 ] || return 1
    echo "${w}x${h}"
}

# Download the first URL that yields real PNG bytes into $1. Remaining args are
# candidate URLs, tried in order.
download_png() {
    local out="$1"; shift
    local url
    for url in "$@"; do
        if download "$url" "$out" && is_png "$out"; then
            return 0
        fi
        rm -f "$out"
    done
    return 1
}
