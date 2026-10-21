{pkgs, ...}: {
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
    codex

    bun

    copyparty
  ];

  programs = {
    fish.enable = true;
    starship.enable = true;
    atuin.enable = true;
    zoxide.enable = true;
  };

  xdg.configFile = {
    "fish/conf.d/bun.fish".source = ../dotfiles/fish/conf.d/bun.fish;
    "fish/conf.d/shell.fish".source = ../dotfiles/fish/conf.d/shell.fish;
  };
}
