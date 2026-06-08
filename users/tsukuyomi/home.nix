{
  config,
  pkgs,
  lib,
  userData,
  ...
}:

{
  imports = [
    ./modules
  ];

  home.stateVersion = "26.05";
}
