{
  pkgs ? import <nixpkgs> { },
}:

{
  # The ataraxia configuration manager
  ataraxia = pkgs.callPackage ./ataraxia { };

  # Example of how to add a package:
  # my-package = pkgs.callPackage ./my-package { };
}
