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

    # Fonts
    sarasa-gothic
    noto-fonts-color-emoji
  ];

  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "Sarasa Term SC" "Noto Color Emoji" ];
      sansSerif = [ "Sarasa Gothic SC" "Noto Color Emoji" ];
      serif     = [ "Sarasa Gothic SC" "Noto Color Emoji" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # Programs that have their own HM module
  programs.kitty.enable = true;
}
