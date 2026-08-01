# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [v5.1.0] -- 2026-08-01

### Added
- **Container mode for image-based systems (`--distrobox`)**: on Bazzite, Silverblue, Kinoite and SteamOS, packages are layered into the next boot image, so Wine cannot be installed into the running system without root and a reboot -- previously the dependency step warned and the install then died on the first Wine call. The installer now creates a distrobox container, installs Wine staging, `winetricks`, the 32-bit graphics and audio libraries and the fonts inside it, and re-runs itself in there. `$HOME` is shared, so the prefix, config, desktop entries, MIME handlers and symlinks still land on the host.
- **Host shims for container installations**: the desktop entry, the file associations and the importer wrapper run on the host, which has no Wine of its own. `~/.config/osu-importer/hostbin/{wine,winepath,wineserver}` bridge into the container, and the generated config points at them, so launching osu! and double-clicking a `.osz` work unchanged. Arguments are handed over through a generated one-shot script, since `distrobox-enter` re-parses its trailing command through a shell and every osu! path contains spaces.
- **The container is remembered**: `--update`, `--health-check`, `--uninstall` and `--launch` find it from the stored configuration, so the flag is only needed for the first install. `--health-check` reports the container itself and looks for `winetricks` inside it; `--uninstall` offers to remove it.
- **`--distrobox-name` and `--distrobox-image`** to override the container name and image (`osu-stable`, `docker.io/library/archlinux:latest`). NVIDIA hosts get their drivers mounted in through distrobox's `--nvidia`.
- **Offer instead of failure**: running the installer with no flags on an image-based system that has no Wine now proposes container mode rather than proceeding into an error.

- **Network precheck before anything is set up**: every step of an installation downloads something -- system packages, MS .NET 4.8 through winetricks, the osu! client, fonts, the RPC bridge, the icons -- so a missing connection used to surface late and differently at each step, worst of all several minutes into the .NET install. A fresh installation now stops immediately with the reason; a prefix that already carries osu! is only warned, since re-applying settings offline is legitimate. Only the hosts the installer actually downloads from are probed, and `curl`'s absence on a bare system falls back to a plain TCP connect instead of reporting the machine as offline.

### Fixed
- **`pkexec` inside a container**: there is no polkit agent to answer it, so package installation used the container's passwordless `sudo` instead.
- **`-h`/`--help` is handled before any prompt**, so asking for the usage text cannot trigger the container question.

---

## [v5.0.3] -- 2026-07-28

### Fixed
- **Application icon was never installed**: Wikimedia stopped serving arbitrary thumbnail widths and now rejects the hardcoded 512px URL with HTTP 400, so `osu-stable-game.png` was missing on every new installation while the `.desktop` entry still pointed at it -- KDE Plasma and other strict icon consumers rendered a placeholder. The launcher icon is now extracted from the installed `osu!.exe` at its native resolution via `icoutils`, with downloads at accepted widths as a fallback.
- **Two osu! clients after a fresh install**: `osu!install.exe` starts the game itself before exiting, so the wine loader returned while the client was still coming up and the installer launched a second one on top of it; both then competed over `osu!.db` and the user configuration. The installer now detects a client the updater already started and waits for it to close instead.
- **Desktop entries went stale on KDE**: `update-desktop-database` and `kbuildsycoca` were never invoked, so Plasma kept serving the cached entry -- icon included -- until the next login. All integration paths (install, update, uninstall, config import) now refresh the icon, desktop, and service caches together.
- **Icons landed in a directory that did not match their size**: files are now written to the hicolor directory matching their actual pixel dimensions, and other size variants of the same icon are removed so a stale copy cannot shadow the current one.
- **A failed download could pass as an icon**: only the file size was checked, so an HTML error page or an SVG served with HTTP 200 was stored under a `.png` name. Downloads are now validated against the PNG signature.
- **One missing icon blocked the others**: all four downloads were gated on a single file, so any other icon that failed was never retried. Each icon is now checked and fetched independently.
- **Install could abort when `~/.local/share/applications` did not exist**: the directory is created before the desktop entries are written.

### Added
- **Icon failures surface in the closing report** in both the TUI and `--silent`, instead of scrolling past as a warning mid-run.
- **`--health-check` verifies the icon files**, not just the `.desktop` entries -- an entry pointing at a missing icon was previously reported as healthy.

### Changed
- **`icoutils` is now a dependency** (`wrestool`, `icotool`), installed alongside the other base packages and provided by the Nix flake.

---

## [v5.0.2] -- 2026-07-10

### Added
- **File-indexer opt-out in the Wine prefix**: the installer drops `.trackerignore` and `.nomedia` markers at the prefix root so background indexers -- GNOME Tracker (`tracker-miners`) and others that honor these markers -- skip the entire Wine tree, above all the large `Songs/` directory that would otherwise be rescanned on every pass. The markers are written idempotently, and `--update` backfills them on prefixes created by earlier versions.

---

## [v5.0.1] -- 2026-06-28

### Fixed
- **Mismatched icon sizes**: the file-type icon sources are 512px but were written into the `128x128` hicolor directory; they are now scaled to match it.
- **MIME registration consolidated**: `.osz`/`.osk`/`.osr` now carry per-type `<icon>` hints, with beatmaps and skins marked `sub-class-of application/zip`; the duplicate MIME packages left by earlier versions -- which could shadow the icon hints -- are removed.

---

## [v5.0.0] -- 2026-06-18 (YY-MM-DD)

### Changed
- **Configuration UI moved from YAD to `gum`**: the dashboard, confirmations, progress, and notifications now render as a terminal TUI. YAD is no longer a dependency anywhere in the installer.
- **Defaults are now `wine-staging` + native Wayland + OpenGL**, reflecting the current stable baseline. Window-driver labels became `Wayland (Recommended)` / `X11 (Fallback)`.
- **Wine selection is treated as a package, not a binary**: `wine-staging` provides the `wine` binary (there is no separate `wine-staging` executable on most distros). Staging is detected via `wine --version`, the binary is resolved through `resolve_wine_bin()`, and dependencies install only when the `wine` binary is genuinely absent.

### Added
- **Batch beatmap import**: dropping several `.osz` at once places the extras into `Songs/` and triggers a single in-game refresh instead of handing each file off separately; single files and skins/replays still use the direct handoff. Import notifications are quiet by default, with `OSU_IMPORTER_DEBUG=1` for verbose output.
- **NixOS support via a Nix flake** (`flake.nix`): `nix run` / `nix develop` provide every dependency, so no system package installation is required. One `install.sh` adapts to NixOS rather than maintaining a separate script.
- **Decorative-glyph font fallback**: a `FontLink\SystemLink` chain to DejaVu Sans / Noto Sans Symbols lets dingbats such as `U+2727` in beatmap titles render instead of showing as boxes, which no CJK font carries.

### Fixed
- **Native Wayland was never actually enabled**: v4.2.0 switched to `WINEWAYLAND=1`, which is a no-op. Reverted to the registry `HKCU\Software\Wine\Drivers\Graphics` key (`wayland,x11`) -- the real driver selector.
- **Unnecessary `wine-staging` reinstall**: the dependency check skips when the `wine` binary is present, so `pkexec`/`pacman` is not invoked when staging is already installed.
- **Noisy install output**: Wine registry and utility commands now redirect both stdout and stderr, so harmless "registry value not found" / "service not started" lines no longer leak to the terminal after the TUI migration.

### Known Issues
- **Wine Mono + sync**: unchanged -- disable FSync/ESync/NTSync when using Wine Mono.
- On NixOS the symbol-glyph fallback needs DejaVu / Noto symbol fonts visible to `fontconfig`; the flake provides them, but a pure dev shell may need them in the system font path.

---

## [v4.2.0] — 2026-03-05 (YY-MM-DD)

### Architecture
- Refactored monolithic `install.sh` into a modular system under `modules/`:
  - `00_logger.sh` — logging and GUI helper functions
  - `01_cli_gui.sh` — CLI argument parser and YAD dashboard
  - `02_deps.sh` — system dependency resolution
  - `03_wine_env.sh` — Wine prefix, graphics, and font setup
  - `04_osu_core.sh` — osu! download, RPC, system integration, symlinks
  - `05_maintenance.sh` — update, uninstall, health check, export/import, launch

### Added
- **CLI silent mode** (`--silent` / `-s`): fully unattended installation without YAD
- **Update mode** (`--update`): re-applies graphics, fonts, RPC, and desktop integration over an existing installation without re-downloading osu!
- **Uninstall** (`--uninstall`): interactive removal of prefix, desktop entries, MIME types, symlinks, and config with confirmation prompt
- **Health check** (`--health-check`): verifies 10 installation components, reports pass/fail in YAD or terminal
- **Config export/import** (`--export-config` / `--import-config <file>`): tar.gz backup with timestamp
- **Debug launch** (`--launch`): starts osu! directly from config with full Wine output in terminal — useful for diagnosing startup issues
- **Convenience symlinks**: creates `~/osu/{Songs,Skins,Logs,Chat}` pointing into the Wine prefix. Path configurable via `--links-dir DIR` or YAD Dashboard field
- **Audio backend selection**: PulseAudio/PipeWire or ALSA, exposed in Dashboard and CLI (`--audio`)
- **GameMode integration**: `gamemoderun` support via `--no-gamemode` toggle
- **FSync/ESync/NTSync toggle**: `--no-sync` flag and Dashboard checkbox
- **.NET runtime selection**: choose between MS .NET 4.8 and Wine Mono (`--dotnet`)
- Module presence validation in `install.sh` before sourcing — clear error if a module file is missing
- `--help` now documents all flags including maintenance commands

### Fixed
- **Discord RPC crash on reinstall**: Wine commands (`net stop`, `taskkill`) now wrapped in `set +e` / `set -e` locally — non-zero exit from "service already stopped" no longer kills the entire script
- **`DRIVERS_INSTALLED` false trigger**: base packages (`curl`, `unzip`, `wine`) no longer trigger a reboot warning — only GPU-specific packages (`nvidia-libs`, `mesa-dri`) do
- **Font directory wiped on Skip**: `rm -f Fonts/*` now only runs after confirming `FONT_SELECTION != "Skip"`
- **Version desync**: `install.sh` header, `log_info`, and `SCRIPT_TITLE` were reporting three different versions (v4.0 / v4.1 / v4.2) — unified to `v4.2.0`
- **YAD progress bar not animating**: all `yad --progress --pulsate` pipes now include `2>&1` — `winetricks`, `wine`, and `curl` write to stderr which the pipe previously discarded
- **Wine Mono + MS .NET conflict**: `setup_wine_prefix` now runs `winetricks remove_mono` before installing .NET 4.8. Running both runtimes simultaneously caused a Mono assertion crash (`mono-error.c:647`) on `System.Environment.Exit` during osu! startup
- Wrapper script now sources `osu-env.conf` at runtime instead of having all variables hardcoded at install time
- `wineserver` and Wine process cleanup after initial osu! setup

### Changed
- `WINEPREFIX` is now consistently passed as an environment variable rather than relying on the global `export` — reduces cross-contamination between subshells
- Wayland support migrated from registry key (`HKCU\Software\Wine\Drivers\Graphics`) to environment variable (`WINEWAYLAND=1`) — compatible with Wine 11.3+
- `_run_package_manager` extracted as internal helper in `02_deps.sh` to avoid code duplication across distro branches
- Default Wine prefix detection checks for legacy `~/.osu-wine` path for backwards compatibility

### Known Issues
- **Wine Mono**: if you select "Wine Mono" as runtime, FSync/ESync/NTSync **must** be disabled — enabling sync with Mono causes the same assertion crash. The generated `osu-env.conf` includes a warning comment about this.
- **Wayland cursor confinement**: on Hyprland and Sway the cursor may not be correctly confined to the window. Use X11 driver if this occurs.
- **NixOS**: automatic dependency installation is not supported. Install `yad` and `wine` manually before running, or use `--silent`.

---

## [v4.0.0] — 2025 (initial public release)

### Added
- YAD-based configuration dashboard
- Multi-distribution support: Arch, Debian/Ubuntu, Fedora, Void Linux
- DXVK and OpenGL renderer selection
- X11 and Wayland window driver selection
- CJK font installation: WenQuanYi, Noto Sans CJK, Koruri, system font linking
- Discord RPC bridge installation via [rpc-bridge](https://github.com/EnderIce2/rpc-bridge)
- MIME type registration for `.osz`, `.osk`, `.osr`
- Desktop entry and application menu integration
- Wrapper script with file import logic and audio latency environment variables
- NixOS detection with manual dependency notice
- Void Linux 32-bit library and GPU driver handling
