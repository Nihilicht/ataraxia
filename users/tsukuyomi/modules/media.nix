{
  config,
  lib,
  pkgs,
  nixataraxia,
  ...
}:

{
  home.packages = with pkgs; [
    obs-studio

    # ImageMagick wrapped with LibRaw for RAW processing
    (nixataraxia.wrapWithDeps {
      package = imagemagick;
      deps = [ libraw ];
    })

    ani-cli
  ];
}
