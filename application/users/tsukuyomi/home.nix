{ pkgs, ... }:
{
  home.packages = with pkgs; [
    htop
  ];

  programs.bash.enable = true;

  home.stateVersion = "23.11";
}
