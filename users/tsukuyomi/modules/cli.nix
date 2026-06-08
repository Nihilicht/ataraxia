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

  xdg.configFile = {
    "fish/conf.d/bun.fish".source = ../dotfiles/fish/conf.d/bun.fish;
    "fish/conf.d/shell.fish".source = ../dotfiles/fish/conf.d/shell.fish;
  };
}
