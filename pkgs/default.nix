{
  inputs,
  pkgs ? import <nixpkgs> {},
}: {
  # Example of how to add a package:
  deepagents-code = pkgs.callPackage ./deepagents-code.nix {
    inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
}
