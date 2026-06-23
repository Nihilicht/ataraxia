{
  description = "A basic NixOS flake";

  inputs = {
    nixpkgs.url = "flake:nixpkgs";
    ataraxia = {
      url = "path:../core";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    honkers-railway-launcher = {
      url = "github:nix-community/home-manager"; # Just use a dummy valid url that evaluates fast
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ataraxia,
      ...
    }@inputs:
    ataraxia.lib.mkSystems {
      root = ./.;
      inputs = inputs;
    };
}
