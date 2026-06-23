{
  description = "Ataraxia Core Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    {
      lib = import ./lib.nix inputs;

      nixosModules.default = import ./module.nix inputs;

      packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          ataraxia = pkgs.rustPlatform.buildRustPackage {
            pname = "ataraxia";
            version = "0.1.0";
            src = ./manager;
            cargoLock = {
              lockFile = ./manager/Cargo.lock;
            };
          };
          default = self.packages.${system}.ataraxia;
        }
      );
    };
}
