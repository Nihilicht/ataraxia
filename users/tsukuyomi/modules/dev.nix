{
  config,
  lib,
  pkgs,
  nixataraxia,
  ...
}:

{
  home.packages = with pkgs; [
    # Private dependency isolation for Helix
    (nixataraxia.wrapWithDeps {
      package = helix;
      deps = [
        lua-language-server
        nixd
        nixfmt
      ];
    })

    gcc
    uv
    gh
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  xdg.configFile."helix".source = ../dotfiles/helix;
}
