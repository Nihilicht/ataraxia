{
  config,
  pkgs,
  lib,
  userData,
  inputs,
  ...
}: {
  imports = [
    inputs.caelestia-shell.homeManagerModules.default
  ];

  programs.caelestia = {
    enable = true;
    cli.enable = true;
  };

  home.stateVersion = "26.05";
}
