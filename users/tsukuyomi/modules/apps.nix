{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    helium # Custom Chromium derivative via overlay
    vesktop # Discord client
    fjordlauncher # Minecraft
    vlc # Media player
    darktable # Photography workflow
    kdePackages.dolphin # File manager
  ];
}
