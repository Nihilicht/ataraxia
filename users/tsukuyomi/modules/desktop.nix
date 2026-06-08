{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    # Wayland ecosystem
    rofi
    swaynotificationcenter
    grim
    satty
    slurp
    cliphist
    hyprpaper
    hypridle
    hyprpolkitagent
    qt6.qtwayland

    # Networking/Tray
    netbird-ui
  ];

  # Programs that have their own HM module
  programs.kitty.enable = true;
}
