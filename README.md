# osu! Linux Installer (Stable)

**Version:** v5.0.0
**License:** MIT
**Languages:** [English](README.md) | [Русский](README_RU.md)

A modular Bash installer for the automated deployment and configuration of the osu! (stable) client on Linux. Prioritizes low-latency performance, correct system integration, and support for modern graphics stacks.

Uses `gum` for a clean terminal (TUI) configuration dashboard. Fully unattended CLI mode is also supported.

## Key Features

- **Multi-distribution:** Arch Linux, Debian/Ubuntu, Fedora, Void Linux, and NixOS (first-class via the bundled Nix flake).
- **Graphics:** OpenGL or DXVK (DirectX → Vulkan translation for reduced input latency).
- **Window system:** Native Wayland (default, no XWayland overhead) or X11 (fallback). The driver is selected via the Wine registry — `WINEWAYLAND=1` alone does nothing.
- **Fonts:** CJK font installation (Noto Sans CJK, WenQuanYi, Koruri, or system linking) plus a symbol-glyph fallback so decorative dingbats in beatmap titles render instead of boxes.
- **Audio:** PulseAudio/PipeWire or ALSA backend, with tuned latency environment variables.
- **Sync:** FSync / ESync / NTSync support (NTSync requires Linux 6.8+ `/dev/ntsync`).
- **GameMode:** Optional [Feral GameMode](https://github.com/FeralInteractive/gamemode) integration.
- **System integration:** Desktop entry, MIME type registration for `.osz` / `.osk` / `.osr`, wrapper script.
- **Convenience symlinks:** `~/osu/{Songs,Skins,Logs,Chat}` pointing into the Wine prefix for easy access.
- **Beatmap importer:** double-click `.osz` / `.osk` / `.osr` to import into the running game; multi-file drops batch-import in a single in-game pass.
- **Maintenance commands:** update, uninstall, health check, config export/import, debug launch.

## System Requirements

- **OS:** Linux (Arch, Debian, Fedora, Void, or derivatives).
- **Dependencies:** `curl`, `unzip`, `winetricks`, `gum` — installed automatically on supported distros.
- **Wine:** `wine-staging` recommended (and the default). Standard `wine` is supported.

> **NixOS users:** First-class via the bundled Nix flake — Nix supplies every dependency, no manual setup. See [NixOS](#nixos).

## Installation

```bash
git clone https://github.com/Kitty-Hivens/linux-osu-stable-installer.git
cd linux-osu-stable-installer
chmod +x install.sh
./install.sh
```

> **Security note:** Root privileges (via `pkexec`) are requested **only** to install missing system packages. osu! itself is installed entirely in the user's home directory.

### NixOS

The repository ships a Nix flake, so Nix supplies every dependency (Wine staging, `gum`, `winetricks`, fonts, `ydotool`, ...) — no system package installation, no `--silent` workaround:

```bash
# one-shot install / configure
nix run github:Kitty-Hivens/linux-osu-stable-installer

# or drop into a dev shell with everything on PATH, then run it yourself
nix develop github:Kitty-Hivens/linux-osu-stable-installer
./install.sh
```

## Configuration Dashboard

On first run, an interactive terminal dashboard appears (powered by `gum`):

| Parameter | Description |
| :--- | :--- |
| **Install Location** | Wine prefix directory. Default: `~/.wine-osu` |
| **Wine Binary** | Auto-detects `wine-staging`. Custom paths (Proton, Wine-GE) can be specified. |
| **Graphics API** | **OpenGL** — standard renderer, good for older hardware. **DXVK** — Vulkan translation, recommended for modern GPUs. |
| **Window Driver** | **Wayland** (default) — native Wine driver, no XWayland overhead. **X11** — fallback for maximum compositor compatibility. |
| **Fonts** | Replaces the Windows UI font to fix CJK character rendering in beatmap lists and chat. |
| **Discord RPC** | Installs [rpc-bridge](https://github.com/EnderIce2/rpc-bridge) for Rich Presence in the Linux Discord client. |
| **.NET Runtime** | **MS .NET 4.8** (recommended) or **Wine Mono** (experimental). See note below. |
| **Audio Backend** | **PulseAudio/PipeWire** (default) or **ALSA** for lowest possible latency. |
| **FSync/ESync** | Sync primitives for reduced CPU overhead. Requires compatible Wine and kernel. |
| **GameMode** | Enables `gamemoderun` wrapper if [GameMode](https://github.com/FeralInteractive/gamemode) is installed. |
| **Symlinks Directory** | Where to create `Songs/Skins/Logs/Chat` shortcuts. Default: `~/osu` |

## CLI Usage

```
./install.sh [OPTIONS]

Installation:
  -p, --prefix DIR       Wine prefix directory (default: ~/.wine-osu)
  -w, --wine BIN         Wine binary or path (default: wine-staging or wine)
  -a, --api API          Graphics API: 'opengl' or 'dxvk'
  -d, --driver DRIVER    Window driver: 'x11' or 'wayland' (default: wayland)
  -f, --font FONT        Font: 'wqy', 'noto', 'koruri', 'system', 'skip'
      --rpc true/false   Install Discord RPC bridge (default: true)
      --dotnet TYPE      Runtime: 'net48' or 'mono'
      --audio TYPE       Audio backend: 'pulse' or 'alsa'
      --no-sync          Disable FSync/ESync/NTSync
      --no-gamemode      Disable GameMode integration
      --links-dir DIR    Symlink directory (default: ~/osu)
  -s, --silent           Unattended mode, no TUI

Maintenance:
      --update           Re-apply settings to existing installation
      --uninstall        Remove osu! and all integration files
      --health-check     Verify installation integrity
      --export-config    Export config to osu-config-backup.tar.gz
      --import-config F  Import config from a backup file
      --launch           Launch osu! with full Wine output (debug mode)
```

## Runtime Selection: .NET 4.8 vs Wine Mono

This is the most important configuration choice:

| | MS .NET 4.8 | Wine Mono |
| :--- | :--- | :--- |
| **Stability** | Recommended | Experimental |
| **FSync/ESync/NTSync** | Safe to enable | Must be disabled (causes crash) |
| **Install time** | ~5-10 min | Instant (bundled) |
| **Crash symptom** | none | `mono-error.c:647` assertion on startup |

If you selected Mono and osu! crashes immediately, either switch to .NET 4.8 via `--update`, or disable sync in `~/.config/osu-importer/osu-env.conf`.

## Post-Install

### Convenience Symlinks

After installation, your osu! data is accessible at:

```
~/osu/
├── Songs  →  ~/.wine-osu/.../osu!/Songs
├── Skins  →  ~/.wine-osu/.../osu!/Skins
├── Logs   →  ~/.wine-osu/.../osu!/Logs
└── Chat   →  ~/.wine-osu/.../osu!/Chat
```

If any of those directories already existed as real folders, the installer backs them up as `Songs.bak.TIMESTAMP`, merges the contents into the Wine prefix, then creates the symlink.

### Importing Beatmaps

Double-click a `.osz`, `.osk`, or `.osr` in your file manager and it imports into the running osu! (the game is launched first if it is not already open). Selecting several `.osz` at once batch-imports them in a single in-game pass instead of one pop-up per file. Notifications are quiet by default — set `OSU_IMPORTER_DEBUG=1` in the config for per-file detail.

### Tweaking Settings

All launch parameters are stored in `~/.config/osu-importer/osu-env.conf`. Edit it directly to adjust audio buffers, sync flags, or VSync:

```bash
# Disable VSync in OpenGL:
export vblank_mode=0

# Lower audio buffer for better latency (may cause crackling on slow systems):
export STAGING_AUDIO_DURATION=5000
export PULSE_LATENCY_MSEC=30

# Verbose beatmap-import notifications (per-file / launching / rescan):
export OSU_IMPORTER_DEBUG=1
```

### Debug Launch

To diagnose startup issues, run osu! directly in the terminal with full Wine output:

```bash
./install.sh --launch
```

## Uninstallation

```bash
./install.sh --uninstall
```

Or manually:

```bash
rm -rf ~/.wine-osu
rm -f ~/.local/share/applications/osu-stable.desktop
rm -f ~/.local/share/applications/osu-importer.desktop
rm -f ~/.local/share/mime/packages/osu-file-types.xml
rm -rf ~/.config/osu-importer
# Remove symlinks:
rm -f ~/osu/Songs ~/osu/Skins ~/osu/Logs ~/osu/Chat
```

## Known Issues

- **Wayland raw input:** the native Wayland driver does not expose true raw input — turn osu!'s Raw Input **off** and set sensitivity via mouse DPI, and run **Borderless** rather than exclusive fullscreen (which flickers on focus changes). If you need hardware-raw input, use the X11 driver instead.
- **Wine Mono + FSync:** Enabling any sync primitive (FSync/ESync/NTSync) with Wine Mono causes a crash at startup (`mono-error.c:647`). Use MS .NET 4.8 or disable sync.
- **NixOS:** Run through the bundled flake (`nix run` / `nix develop`) so Nix provides the dependencies — see [NixOS](#nixos).

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
