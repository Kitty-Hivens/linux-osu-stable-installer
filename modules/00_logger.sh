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

# True when the hosts the installation actually pulls from are reachable. Only those hosts
# are contacted -- nothing is sent anywhere the install would not have contacted anyway.
# Any HTTP answer counts: the point is reachability, not a specific status code.
network_available() {
    local host
    if command -v curl &> /dev/null; then
        for host in https://m1.ppy.sh https://github.com; do
            curl -s --max-time 8 -o /dev/null "$host" && return 0
        done
        return 1
    fi

    # curl is itself one of the packages the dependency step installs, so on a bare system
    # fall back to a plain TCP connect rather than reporting the machine as offline. It gets
    # an explicit deadline: a blackholed network drops the SYN silently, and the kernel would
    # otherwise retry for minutes -- in a check whose whole purpose is to fail quickly.
    for host in m1.ppy.sh github.com; do
        if command -v timeout &> /dev/null && command -v bash &> /dev/null; then
            timeout 8 bash -c 'exec 3<>"/dev/tcp/$0/443"' "$host" 2>/dev/null && return 0
        else
            # Nothing external is available to bound this one -- the probe is a shell
            # builtin precisely so it still works there, at the mercy of the SYN retries.
            (exec 3<>"/dev/tcp/$host/443") 2>/dev/null && return 0
        fi
    done
    return 1
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

# True if $1 starts with the DOS header every Windows executable carries. A captive portal
# or an error page served with HTTP 200 passes a plain size check, and the failure would
# only surface later as Wine refusing to run the file.
is_pe() {
    [ -s "$1" ] || return 1
    [ "$(head -c 2 "$1" 2>/dev/null)" = "MZ" ]
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

# ==============================================================================
# Wine version guard
# ==============================================================================
# Wine releases that break osu!: the client throws OutOfMemoryException while reading
# osu!.db, renames the real database to osu!.db.<ticks>.bak and rebuilds an empty one --
# on every launch, so the song list comes up empty and stays that way until the backup is
# put back by hand. Verified by running 11.15 and 11.16 against the same prefix and the
# same 32 MB database: 11.15 reads it, 11.16 fails within ten seconds. Neither the file
# nor its size is at fault -- 11.16 rejects a 1 MB database it wrote itself moments earlier.
WINE_BROKEN_VERSIONS="11.16"

# Echo the bare version out of whatever reports one: "wine-11.16 (Staging)", "wine-11.16",
# "11.16-1.1" all yield "11.16". Empty when the string carries no version at all.
wine_version_number() {
    printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

# True when bare version $1 is on the broken list.
wine_version_is_broken() {
    local v="$1" bad
    [ -n "$v" ] || return 1
    for bad in $WINE_BROKEN_VERSIONS; do
        [ "$v" = "$bad" ] && return 0
    done
    return 1
}

# Bare version of the Wine binary $1. Empty when it cannot be run at all.
wine_binary_version() {
    local out
    out=$("$1" --version 2>/dev/null) || return 1
    wine_version_number "$out"
}

# What the breakage looks like, for every message that has to explain it. Kept in one
# place so the installer, the launcher and the health check tell the same story.
wine_broken_blurb() {
    printf '%s' "osu! cannot read its beatmap database on this Wine version.

Every launch renames osu!.db to osu!.db.<number>.bak and builds an empty one in its place,
so the song list comes up empty. Nothing is deleted -- the real database is in those .bak
files -- but it has to be restored by hand after every start."
}
