{
  lib,
  pkgs,
  ataraxia,
  ...
}: {
  # Default home state version
  home.stateVersion = lib.mkDefault "26.05";

  # Shim the legacy nixataraxia.wrapWithDeps helper outside core using core's wrapPackage
  _module.args.nixataraxia = {
    wrapWithDeps = {
      package,
      deps ? [],
    }:
      ataraxia.lib.wrapPackage {
        inherit pkgs deps;
        pkg = package;
      };
  };
}
