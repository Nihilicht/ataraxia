{ config, pkgs, userData, ... }:

{
  # home.username and home.homeDirectory are now automatically handled by users/default.nix

  home.stateVersion = "26.05";

  home.packages = [
    # pkgs.hello
  ];
}
