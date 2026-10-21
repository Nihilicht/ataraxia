{
  config,
  lib,
  pkgs,
  ataraxia,
  ...
}: {
  home.packages = with pkgs; [
    google-chrome # Required for Antigravity IDE Browser Agent
    helium # Custom Chromium derivative via overlay
    vesktop # Discord client
    fjordlauncher # Minecraft
    honkers-railway-launcher # Honkai: Star Rail launcher via aagl overlay
    vlc # Media player
    darktable # Photography workflow
    kdePackages.dolphin # File manager
    (ataraxia.lib.wrapPackage {
      inherit pkgs;
      pkg = antigravity-ide.override {useFHS = true;};
      deps = [
        lua-language-server
        nixd
        nixfmt
      ];
    })
    obsidian
    loupe
  ];
}
