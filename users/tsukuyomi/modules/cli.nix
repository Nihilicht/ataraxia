{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = with pkgs; [
    wl-clipboard
    fastfetch
    jq
    unzip
    psmisc
    dust
    aria2
    parallel
    bore-cli
    typst

    # AI / CLI Agents
    gemini-cli
    codex
  ];

  programs.fish.enable = true;
  programs.starship.enable = true;
  programs.atuin.enable = true;
  programs.zoxide.enable = true;
}
