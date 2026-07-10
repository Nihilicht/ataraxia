{
  pkgs,
  lib,
  users,
  ...
}: let
  hasAagl = builtins.any (u: builtins.elem "aagl" (u.inputs or [])) users;
in
  {
    # Enable dynamic linker stub for unpatched binaries (e.g. rust-analyzer, VS Code extensions)
    programs.nix-ld = {
      enable = true;
      # Provide standard C libraries that Rust/C++ binaries commonly expect
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
      ];
    };

    environment = {
      # System-wide packages
      systemPackages = with pkgs; [
        zellij # Terminal multiplexer
        helix # Modal text editor
        wget # Network downloader
        wl-clipboard # Wayland clipboard utilities
        psmisc # Utilities like fuser, killall
        smartmontools # Disk monitoring
        devenv # Developer environment manager
        antigravity-cli
      ];

      # Set Helix (hx) as the default editor for the terminal and system tools
      variables = {
        EDITOR = "hx";
        VISUAL = "hx";
      };
    };
  }
  // lib.optionalAttrs hasAagl {
    programs.honkers-railway-launcher.enable = true;
  }
