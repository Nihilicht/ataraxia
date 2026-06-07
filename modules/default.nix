{ config, pkgs, ... }:

{
  imports = [
    ./system.nix
    ./hardware.nix
    ./programs.nix
    ./desktop.nix
    # Add more global modules here
  ];
}
