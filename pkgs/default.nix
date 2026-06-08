{
  pkgs ? import <nixpkgs> { },
}:

{
  # The ataraxia configuration manager
  ataraxia = pkgs.callPackage ./ataraxia-cli.nix { };

  # Example of how to add a package:
  # my-package = pkgs.callPackage ./my-package { };
}
