{
  config,
  lib,
  pkgs,
  ataraxia,
  ...
}: {
  home.packages = with pkgs; [
    helium # Custom Chromium derivative via overlay
    vesktop # Discord client
    fjordlauncher # Minecraft
    honkers-railway-launcher # Honkai: Star Rail launcher via aagl overlay
    vlc # Media player
    darktable # Photography workflow
    kdePackages.dolphin # File manager
    (ataraxia.lib.wrapPackage {
      inherit pkgs;
      pkg = antigravity-ide.override {useFHS = false;};
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
