{
  description = "osu! stable (Wine) installer with full Linux integration -- gum TUI, batch importer, native Wayland";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forEach = f: nixpkgs.lib.genAttrs systems
        (system: f system nixpkgs.legacyPackages.${system});

      # Everything install.sh and the generated wrapper need at runtime. On NixOS the
      # installer's package-manager step finds these already on PATH and installs nothing.
      runtimeDeps = pkgs: with pkgs; [
        bash coreutils gnugrep gnused findutils
        wineWowPackages.staging        # the binary is `wine`; staging is the baseline
        winetricks
        gum                            # TUI (this installer dropped yad)
        curl unzip
        fontconfig                     # fc-list, for the symbol-glyph fallback
        dejavu_fonts                   # DejaVu Sans -- carries U+2727 and other dingbats
        noto-fonts noto-fonts-cjk-sans # CJK + Noto symbols
        libnotify                      # notify-send (wrapper notifications)
        ydotool                        # synthetic F5 for the batch importer (--rescan)
        gamemode                       # gamemoderun
        desktop-file-utils shared-mime-info
      ];
    in {
      # `nix develop` -> all deps on PATH, then run `./install.sh` yourself.
      devShells = forEach (system: pkgs: {
        default = pkgs.mkShell {
          packages = runtimeDeps pkgs;
          shellHook = "echo 'osu! installer shell ready -- run: ./install.sh'";
        };
      });

      # `nix run github:Kitty-Hivens/linux-osu-stable-installer` -> install / configure.
      apps = forEach (system: pkgs: {
        default = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "osu-install" ''
            export PATH=${pkgs.lib.makeBinPath (runtimeDeps pkgs)}:$PATH
            exec ${self}/install.sh "$@"
          ''}/bin/osu-install";
        };
      });
    };
}
