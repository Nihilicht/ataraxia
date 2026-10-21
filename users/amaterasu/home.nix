{
  config,
  pkgs,
  lib,
  userData,
  inputs,
  ...
}: {
  imports = [
  ];

  programs.kitty.enable = true;

  home.stateVersion = "26.05";
}
