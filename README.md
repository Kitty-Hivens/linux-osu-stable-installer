# osu! Linux Installer (Stable)

**Version:** v4.0.0
**License:** MIT
**Languages:** [English](README.md) | [Русский](README_RU.md)

A comprehensive Bash script for the automated deployment and configuration of the osu! (stable) client on Linux environments. This solution prioritizes low-latency performance, correct system integration, and support for modern graphics stacks.

The script utilizes `yad` (Yet Another Dialog) to provide a graphical configuration dashboard prior to installation.

## Key Features

* **Multi-Distribution Support:** Automatic dependency resolution for Arch Linux, Debian/Ubuntu, Fedora, and Void Linux.
* **Graphics Stack:**
    * **OpenGL:** Standard stable renderer.
    * **DXVK:** Translation of DirectX 9/11 to Vulkan to reduce driver overhead.
* **Window System:**
    * **X11:** Standard Wine driver (Recommended for stability).
    * **Wayland:** Enables the experimental native Wayland driver via Wine registry to bypass XWayland latency.
* **Fonts & Localization:**
    * Automatic download and registry patching for CJK fonts (WenQuanYi, Noto Sans, Koruri).
    * Fixes glyph rendering issues in beatmap lists and chat.
    * Enables Font Smoothing.
* **Audio & Latency:** Applies environment variables to minimize audio buffer latency in PulseAudio/PipeWire.
* **System Integration:**
    * Desktop entry creation.
    * MIME type registration: automatic import of `.osz`, `.osk`, and `.osr` files via double-click.
    * Wrapper script to prevent multiple instance execution.

## System Requirements

* **OS:** Linux (Arch, Debian, Fedora, Void, or derivatives). NixOS is partially supported (requires manual `yad` installation).
* **Dependencies:** `curl`, `unzip`, `winetricks`, `yad`. (Installed automatically on supported systems).
* **Wine:** `wine-staging` is recommended for performance, though stable branches are supported.

## Installation

### 1. Clone Repository
```bash
git clone https://github.com/Kitty-Hivens/linux-osu-stable-installer.git
cd linux-osu-stable-installer
````

### 2\. Execute Installer

```bash
chmod +x osu!install.sh
./osu!install.sh
```

> **Security Note:** The script requests root privileges (via `pkexec`) **only** to install missing system packages (drivers, `yad`, `wine`) via your system's package manager. The game itself is installed in the user's home directory.

## Configuration Dashboard

Upon execution, a configuration window will appear. Below is a description of the available parameters:

| Parameter | Description |
| :--- | :--- |
| **Install Location** | Directory for the Wine prefix. Default: `~/.wine-osu`. |
| **Wine Binary** | Selection of the Wine executable. The script automatically detects `wine-staging`. Custom paths (e.g., Proton or Wine-GE) can be manually specified. |
| **Graphics API** | **OpenGL**: Standard renderer. Recommended for legacy hardware.<br>**DXVK**: Vulkan translation layer. Recommended for modern GPUs to improve frame pacing and reduce input lag. |
| **Window Driver** | **X11**: Legacy driver. Stable and compatible with all window managers.<br>**Wayland**: Native Wine Wayland driver. Eliminates XWayland overhead. *Experimental.* |
| **Fonts** | Selects a replacement for the standard Windows UI font to fix CJK character rendering. |
| **Discord RPC** | Installs a bridge application to broadcast game status ("Rich Presence") to the Linux Discord client. |

## Technical Implementation Details

### Wrapper Script

The installer generates a wrapper script at `~/.config/osu-importer/osu_importer_wrapper.sh`. This script handles:

1.  **Environment Variables:**
      * `STAGING_AUDIO_DURATION=10000`: Audio buffer reduction.
      * `PULSE_LATENCY_MSEC=60`: PulseAudio optimization.
      * `LC_ALL=en_US.UTF-8`: Locale enforcement.
2.  **File Handling:** Checks if the game is running before importing files. If running, uses IPC to send the file; if not, launches the game with the file as an argument.

### Uninstallation

The installation is isolated within the prefix. To remove:

1.  Delete the prefix directory (Default: `~/.wine-osu`).
2.  Remove integration files:
    ```bash
    rm ~/.local/share/applications/osu-stable.desktop
    rm ~/.local/share/applications/osu-importer.desktop
    rm -rf ~/.config/osu-importer
    ```

## Known Issues

  * **NixOS:** Automatic dependency resolution is not possible due to OS architecture. Install `yad` manually via `configuration.nix` or `nix-env` before running.
  * **Wayland Driver:** The native Wayland driver may exhibit cursor confinement issues on certain compositors (Hyprland, Sway). If issues arise, reinstall using **X11** or edit the registry key `HKCU\Software\Wine\Drivers\Graphics`.

## License

Distributed under the MIT License. See [LICENSE](https://www.google.com/search?q=LICENSE) for more information.
