{ pkgs, ... }:

{
  # Using programs.<name>.enable instead of systemPackages provides
  # better integration (shell completions, policies, etc.)
  programs = {
    git.enable = true;
    fish.enable = true;

    # Main window manager.
    hyprland = {
      enable = true;
      xwayland.enable = false; # Pure Wayland setup for performance and security.
      withUWSM = true; # Universal Wayland Session Manager for better session handling.
    };

    # Enable dynamic linker stub for unpatched binaries (like cargo outputs)
    nix-ld = {
      enable = true;
      # Provide standard C libraries that Rust binaries commonly expect
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
      ];
    };
  };

  environment = {
    # System-wide packages.
    systemPackages = with pkgs; [
      ataraxia # Custom configuration manager
      zellij # Terminal multiplexer
      helix # Modal text editor
      wget # Network downloader
      home-manager # User configuration management
      quickshell # Used for the custom greeter
      cage # Kiosk compositor for greeter
      wl-clipboard # Wayland clipboard utilities
      psmisc # Helpful utilities like fuser and killall
      smartmontools
    ];

    # Set Helix (hx) as the default editor for the terminal and system tools.
    variables = {
      EDITOR = "hx";
      VISUAL = "hx";
    };
  };
}
