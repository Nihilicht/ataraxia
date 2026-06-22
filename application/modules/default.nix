{ pkgs, ... }:
{
  # System-wide packages and utilities
  environment.systemPackages = with pkgs; [
    curl
    git
    vim
  ];
}
