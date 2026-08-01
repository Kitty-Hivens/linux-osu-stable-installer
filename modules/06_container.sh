#!/bin/bash
# Module: Distrobox container mode (immutable / no-root hosts)
#
# On ostree-based systems -- Bazzite, Silverblue, Kinoite, SteamOS -- Wine cannot be
# installed into the running system without root and a reboot. This module puts the
# dependencies in a distrobox container instead, re-runs the installer inside it, and
# leaves behind host-side shims so the desktop entry and file associations keep working
# from outside the container.

DISTROBOX_MODE=false
DISTROBOX_NAME="osu-stable"
DISTROBOX_IMAGE="docker.io/library/archlinux:latest"

# ==============================================================================
# DETECTION
# ==============================================================================

# True when this process already runs inside a container.
container_active() {
    [ -f /run/.containerenv ] || [ -f /run/.toolboxenv ] || [ -f /.dockerenv ] \
        || [ -n "${CONTAINER_ID:-}" ] || [ -n "${DISTROBOX_ENTER_PATH:-}" ]
}

# True on image-based systems where package installs need root plus a reboot.
host_is_immutable() {
    [ -f /run/ostree-booted ] && return 0
    command -v rpm-ostree &> /dev/null && return 0
    grep -qiE '^VARIANT_ID=.*(silverblue|kinoite|sericea|onyx|coreos|bazzite|steamos)' /etc/os-release 2>/dev/null
}

_host_has_nvidia() {
    [ -d /proc/driver/nvidia ] && return 0
    command -v nvidia-smi &> /dev/null && return 0
    lspci 2>/dev/null | grep -qi "nvidia"
}

# ==============================================================================
# DISTROBOX FRONT-END
# distrobox ships both a single `distrobox <verb>` entry point and the older
# standalone `distrobox-<verb>` scripts; either one is enough.
# ==============================================================================

_db() {
    local verb="$1"; shift
    if command -v distrobox &> /dev/null; then
        distrobox "$verb" "$@"
    elif command -v "distrobox-$verb" &> /dev/null; then
        "distrobox-$verb" "$@"
    else
        return 127
    fi
}

_container_manager() {
    command -v podman &> /dev/null && { echo podman; return 0; }
    command -v docker &> /dev/null && { echo docker; return 0; }
    return 1
}

container_exists() {
    local name="$1" mgr
    mgr=$(_container_manager) || return 1
    if [ "$mgr" = "podman" ]; then
        podman container exists "$name"
    else
        docker container inspect "$name" &> /dev/null
    fi
}

ensure_container_tooling() {
    if ! command -v distrobox &> /dev/null && ! command -v distrobox-enter &> /dev/null; then
        notify_error "--distrobox needs distrobox, which is not installed.

Bazzite, Silverblue and Kinoite ship it preinstalled.
Elsewhere, install it from your package manager, or without root:
  curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local"
    fi

    if ! _container_manager > /dev/null; then
        notify_error "--distrobox needs podman (or docker) on the host, and neither is installed.

podman cannot be installed without root, so on a locked-down system ask an
administrator for it -- every immutable distro this mode targets ships it already."
    fi
}

# ==============================================================================
# RUNNING COMMANDS INSIDE THE CONTAINER
# ==============================================================================

# Hand the command over as a generated one-shot script rather than as trailing arguments to
# distrobox-enter. Current versions exec the argument vector unchanged, but the `su` path
# used for unshared groups routes it through a shell, and the environment is rebuilt from a
# filtered `printenv` that silently drops any value containing a quote, a `$` or a newline.
# A single whitespace-free path is immune to all of that, and the script itself pins the
# argument vector and the environment exactly.
_container_exec() {
    local runtime script rc
    runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/osu-importer"
    if ! mkdir -p "$runtime"; then
        log_error "Cannot create the handover directory: $runtime"
        return 1
    fi
    script="$runtime/cmd.$$.sh"

    {
        printf '#!/bin/bash\n'
        printf 'exec'
        printf ' %q' "$@"
        printf '\n'
    } > "$script"
    chmod +x "$script"

    if _db enter --name "$DISTROBOX_NAME" -- "$script"; then rc=0; else rc=$?; fi
    rm -f "$script"
    return $rc
}

# Translate a host path to where the container sees it. $HOME is bind-mounted at the same
# location; everything else is only reachable through the /run/host mount.
_container_path() {
    case "$1" in
        "$HOME"|"$HOME"/*) printf '%s' "$1" ;;
        *)                 printf '/run/host%s' "$1" ;;
    esac
}

# ==============================================================================
# CONTAINER CREATION AND DEPENDENCY BOOTSTRAP
# ==============================================================================

create_distrobox_container() {
    if container_exists "$DISTROBOX_NAME"; then
        log_info "Using existing distrobox container '$DISTROBOX_NAME'."
        return 0
    fi

    log_info "Creating distrobox container '$DISTROBOX_NAME' from $DISTROBOX_IMAGE..."
    if [ "$SILENT_MODE" = false ]; then
        notify_user "Creating the osu! container.\nThe image download runs once and takes a while."
    fi

    local create_args=(--name "$DISTROBOX_NAME" --image "$DISTROBOX_IMAGE" --yes)

    # Mesa works from the container's own 32-bit stack, but the NVIDIA userspace has to
    # match the host kernel module exactly -- distrobox mounts the host's copy in.
    if _host_has_nvidia; then
        if _db create --help 2>&1 | grep -q -- '--nvidia'; then
            log_info "  NVIDIA GPU detected -- mounting the host drivers into the container."
            create_args+=(--nvidia)
        else
            log_warn "  NVIDIA GPU detected, but this distrobox has no --nvidia flag; OpenGL may fall back to software."
        fi
    fi

    _db create "${create_args[@]}" \
        || notify_error "Failed to create the distrobox container '$DISTROBOX_NAME'. See $LOG_FILE."
}

# Package sets per container image family. Kept generous on purpose: a missing 32-bit
# library surfaces much later as an opaque Wine crash.
_container_setup_script() {
    cat << 'CEOF'
set -e
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

if command -v pacman > /dev/null 2>&1; then
    # osu! stable is a 32-bit program, and Wine's 32-bit libraries live in multilib.
    # A normal Arch install ships that section commented out; the container image drops
    # it altogether, so it has to be appended rather than uncommented.
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        echo "Enabling the multilib repository..."
        if grep -q '^#\[multilib\]' /etc/pacman.conf; then
            $SUDO sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        else
            printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' \
                | $SUDO tee -a /etc/pacman.conf > /dev/null
        fi
    fi
    # A bootstrap interrupted half-way leaves the database locked, and every later attempt
    # then fails with nothing but "unable to lock database". Clear it, but only when no
    # pacman is actually running -- the container shares the host's process namespace.
    if [ -e /var/lib/pacman/db.lck ] && ! pgrep -x pacman > /dev/null 2>&1; then
        echo "Clearing a stale pacman lock left by an interrupted run..."
        $SUDO rm -f /var/lib/pacman/db.lck
    fi

    $SUDO pacman -Syu --noconfirm --needed \
        wine-staging winetricks cabextract icoutils gum curl unzip \
        lib32-gnutls lib32-libpulse lib32-alsa-lib lib32-alsa-plugins \
        lib32-mesa lib32-libxcomposite lib32-libxrandr \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        fontconfig noto-fonts noto-fonts-cjk noto-fonts-extra ttf-dejavu \
        desktop-file-utils shared-mime-info gtk-update-icon-cache
elif command -v dnf > /dev/null 2>&1; then
    $SUDO dnf install -y \
        wine winetricks cabextract icoutils curl unzip fontconfig \
        google-noto-sans-cjk-fonts google-noto-sans-symbols2-fonts dejavu-sans-fonts
elif command -v apt > /dev/null 2>&1; then
    $SUDO dpkg --add-architecture i386
    $SUDO apt update
    $SUDO apt install -y \
        wine wine32 winetricks cabextract icoutils curl unzip fontconfig \
        fonts-noto-cjk fonts-dejavu
else
    echo "[ERROR] Container image has none of pacman/dnf/apt -- cannot install Wine." >&2
    exit 1
fi

# Stamped only after the whole set landed, and container-local so it disappears together
# with the container. A half-finished transaction leaves `wine` in place but the rest
# missing, which this marker refuses to mistake for a finished bootstrap.
$SUDO touch /etc/osu-installer-container-ready
CEOF
}

bootstrap_container_deps() {
    if _container_exec bash -c '[ -f /etc/osu-installer-container-ready ]' &> /dev/null; then
        log_info "Container '$DISTROBOX_NAME' is already provisioned -- skipping the dependency bootstrap."
        return 0
    fi

    log_info "Installing Wine and helpers inside '$DISTROBOX_NAME' (first run takes several minutes)..."
    local setup
    setup=$(_container_setup_script)
    _container_exec bash -c "$setup" \
        || notify_error "Dependency installation inside '$DISTROBOX_NAME' failed. See $LOG_FILE."
}

# ==============================================================================
# RE-ENTRY
# ==============================================================================

# Set DISTROBOX_MODE/NAME/IMAGE from the command line, falling back to what the last
# install recorded -- that is what makes a plain `--update` return to the container.
container_prescan() {
    local args=("$@") i=0 seen_flag=false
    while [ $i -lt ${#args[@]} ]; do
        case "${args[$i]}" in
            --distrobox)       DISTROBOX_MODE=true; seen_flag=true ;;
            --distrobox-name)  i=$((i + 1)); DISTROBOX_NAME="${args[$i]:-$DISTROBOX_NAME}" ;;
            --distrobox-image) i=$((i + 1)); DISTROBOX_IMAGE="${args[$i]:-$DISTROBOX_IMAGE}" ;;
        esac
        i=$((i + 1))
    done

    if [ "$seen_flag" = false ]; then
        local stored
        stored=$(_get_stored "$HOME/.config/osu-importer/osu-env.conf" INSTALLER_DISTROBOX_NAME 2>/dev/null) || stored=""
        if [ -n "$stored" ]; then
            DISTROBOX_MODE=true
            DISTROBOX_NAME="$stored"
        fi
    fi
}

# Create the container if needed, then run the installer itself inside it. $HOME is shared,
# so the prefix, config, desktop entries and symlinks all land on the host regardless.
run_in_distrobox() {
    local installer="$1"; shift
    local inner rc

    ensure_container_tooling
    create_distrobox_container
    bootstrap_container_deps

    inner=$(_container_path "$installer")
    if ! _container_exec bash -c '[ -x "$1" ]' bash "$inner"; then
        notify_error "The container cannot reach the installer at:
  $inner

Put the repository somewhere under $HOME and run it again."
    fi

    log_info "Re-running the installer inside '$DISTROBOX_NAME'..."
    if _container_exec "$inner" "$@" --distrobox --distrobox-name "$DISTROBOX_NAME"; then rc=0; else rc=$?; fi
    return $rc
}

# Someone running the installer for the first time on an image-based system has no way to
# get Wine at all -- offer the container here rather than failing deep inside the
# dependency step with a package manager error.
container_offer_fallback() {
    command -v wine &> /dev/null && return 0
    host_is_immutable || return 0

    log_warn "This system installs packages through an image (ostree), and Wine is not present."

    if [ "$SILENT_MODE" = true ]; then
        notify_error "Wine is missing, and this system cannot install it without root and a reboot.
Re-run with --distrobox to put Wine into a container instead."
    fi

    local answer=""
    if command -v gum &> /dev/null; then
        gum confirm "Install osu! into a distrobox container instead?" && answer="y"
    else
        read -rp "Install osu! into a distrobox container instead? [Y/n] " answer || true
        answer="${answer:-y}"
    fi

    case "${answer,,}" in
        y|yes) DISTROBOX_MODE=true ;;
        *)     notify_error "Wine cannot be installed on this system without root. Nothing was changed." ;;
    esac
}

# The prefix has to be a host path the container sees at the same location, or the whole
# installation would silently land inside the container and vanish with it.
container_validate_paths() {
    local path parent
    for path in "$WINE_PREFIX" "$LINKS_DIR"; do
        case "$path" in
            "$HOME"|"$HOME"/*) continue ;;
        esac
        parent=$(dirname "$path")
        [ -d "$parent" ] || notify_error "In --distrobox mode '$path' is not visible inside the container.
Choose a location under $HOME instead."
        log_warn "'$path' sits outside \$HOME -- verify the container really shares $parent."
    done
}

# ==============================================================================
# HOST SHIMS
# The .desktop entries, MIME handlers and the importer wrapper all run on the host, where
# Wine does not exist. These shims are what the generated config points at: named after the
# real binaries so the wrapper's own `${WINE_BIN%/*}/winepath` lookup keeps working.
# ==============================================================================

CONTAINER_BIN_DIR="$HOME/.config/osu-importer/hostbin"

write_container_shims() {
    local runner="$CONTAINER_BIN_DIR/container-run.sh" bin

    mkdir -p "$CONTAINER_BIN_DIR"

    cat > "$runner" << REOF
#!/bin/bash
# Runs one binary from the osu! distrobox container (generated by the installer).
DISTROBOX_NAME="$DISTROBOX_NAME"
REOF

    cat >> "$runner" << 'REOF'
set -u

BIN="${1:?no binary given}"; shift

if ! command -v distrobox > /dev/null 2>&1 && ! command -v distrobox-enter > /dev/null 2>&1; then
    echo "osu!: distrobox is missing -- cannot reach the '$DISTROBOX_NAME' container." >&2
    notify-send "osu!" "distrobox is missing; the game container cannot be started." 2>/dev/null || true
    exit 127
fi

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/osu-importer"
mkdir -p "$RUNTIME" || { echo "osu!: cannot use $RUNTIME" >&2; exit 1; }
find "$RUNTIME" -maxdepth 1 -name 'cmd.*.sh' -mmin +120 -delete 2>/dev/null || true

# Same handover trick the installer uses. It matters most here: Wine takes its entire
# configuration from the environment, and distrobox rebuilds that environment from a
# filtered `printenv` which drops any value holding a quote, a `$` or a newline. Re-exporting
# inside the container is what makes the prefix and the sync flags arrive intact.
CMD="$RUNTIME/cmd.$$.sh"
{
    printf '#!/bin/bash\n'
    for _var in $(compgen -e); do
        case "$_var" in
            WINE*|WAYLAND_DISPLAY|DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|\
            PULSE_*|PIPEWIRE_*|STAGING_*|SDL_*|DXVK_*|VKD3D_*|MESA_*|__GL*|__NV*|\
            LANG|LC_*|vblank_mode|OSU_*)
                printf 'export %s=%q\n' "$_var" "${!_var}"
                ;;
        esac
    done
    printf 'exec %q' "$BIN"
    [ "$#" -gt 0 ] && printf ' %q' "$@"
    printf '\n'
} > "$CMD"
chmod +x "$CMD"

if command -v distrobox > /dev/null 2>&1; then
    distrobox enter --name "$DISTROBOX_NAME" -- "$CMD"
else
    distrobox-enter --name "$DISTROBOX_NAME" -- "$CMD"
fi
rc=$?

rm -f "$CMD"
exit $rc
REOF
    chmod +x "$runner"

    for bin in wine winepath wineserver; do
        cat > "$CONTAINER_BIN_DIR/$bin" << 'SEOF'
#!/bin/bash
exec "${0%/*}/container-run.sh" "${0##*/}" "$@"
SEOF
        chmod +x "$CONTAINER_BIN_DIR/$bin"
    done

    WINE_BIN_HOST="$CONTAINER_BIN_DIR/wine"
    log_info "Host shims for the container written to $CONTAINER_BIN_DIR"
}

# Drop the container an installation was using. The shims live inside the config directory
# and are removed along with it by the uninstaller.
remove_distrobox_container() {
    local name="$1"
    [ -n "$name" ] || return 0
    command -v distrobox &> /dev/null || command -v distrobox-rm &> /dev/null || return 0
    container_exists "$name" || return 0

    log_info "Removing distrobox container '$name'..."
    _db rm --force "$name" &> /dev/null || _db rm "$name" --force &> /dev/null || \
        log_warn "Could not remove the container '$name' -- remove it with: distrobox rm --force $name"
}
