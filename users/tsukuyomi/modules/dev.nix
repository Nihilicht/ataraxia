{
  pkgs,
  ataraxia,
  ...
}: {
  home.packages = with pkgs; [
    # Private dependency isolation for Helix
    (ataraxia.lib.wrapPackage {
      inherit pkgs;
      pkg = helix;
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

  xdg.configFile."helix".source = ../dotfiles/helix;
}
