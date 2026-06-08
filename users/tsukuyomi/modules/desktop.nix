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

    # Satisfy tsukuyomi-env assertion
    uwsm
  ];

  # Programs that have their own HM module
  programs.kitty.enable = true;
}
