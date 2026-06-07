{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium = {
      url = "github:schembriaiden/helium-browser-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tsukuyomi-env = {
      url = "github:Nihilicht/tsukuyomi-env";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      manifest = fromTOML (builtins.readFile ./manifest.toml);

      # Pass all inputs to overlays
      overlays = import ./overlays { inherit inputs; };

      # Helper to filter users for a specific host
      getEnabledUsers =
        hostCfg: builtins.filter (u: builtins.elem u.name (hostCfg.users or [ ])) manifest.users;
    in
    {
      nixosConfigurations = builtins.listToAttrs (
        map (hostCfg: {
          name = hostCfg.name;
          value = nixpkgs.lib.nixosSystem {
            system = hostCfg.arch;
            specialArgs = {
              hostName = hostCfg.name;
              enabledUsers = getEnabledUsers hostCfg;
              inherit inputs;
            };
            modules = [
              ./hosts/${hostCfg.name}/default.nix
              ./users/default.nix
              ./modules/default.nix
              inputs.aagl.nixosModules.default
              home-manager.nixosModules.home-manager
              (
                { ... }:
                {
                  nixpkgs.overlays = builtins.attrValues overlays;
                  nix.registry.nixpkgs.flake = nixpkgs;
                }
              )
            ];
          };
        }) manifest.hosts
      );
    };
}
