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

    fjordlauncher = {
      url = "github:hero-persson/FjordLauncherUnlocked";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tsukuyomi-env = {
      url = "github:Nihilicht/tsukuyomi-env";
      inputs.nixpkgs.follows = "nixpkgs";
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

      # Global library
      nixataraxia = import ./lib;

      # Registered environments: maps the name in manifest.toml to the input flake
      environments = import ./lib/environments.nix { lib = nixpkgs.lib; } {
        tsukuyomi = inputs.tsukuyomi-env;
      };

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
              inherit
                inputs
                nixataraxia
                hostCfg
                environments
                ;
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

      homeConfigurations =
        builtins.listToAttrs (
          builtins.concatMap (hostCfg:
            let
              pkgs = import nixpkgs {
                system = hostCfg.arch;
                overlays = builtins.attrValues overlays;
              };
              enabledUsers = getEnabledUsers hostCfg;
              hmUsers = builtins.filter (u: u.home or false) enabledUsers;
            in
            map (user:
              let
                envName = user.environment or "";
                isValidEnv = builtins.hasAttr envName environments;
                envModule = if isValidEnv then [ environments.${envName} ] else [ ];
              in
              {
                name = "${user.name}@${hostCfg.name}";
                value = home-manager.lib.homeManagerConfiguration {
                  inherit pkgs;
                  extraSpecialArgs = {
                    nixataraxia = nixataraxia {
                      inherit pkgs;
                      lib = pkgs.lib;
                    };
                    inherit inputs environments;
                  };
                  modules = [
                    ./users/${user.name}/home.nix
                    {
                      home.username = user.name;
                      home.homeDirectory = "/home/${user.name}";
                      _module.args.userData = user;
                      env.enable = isValidEnv;
                    }
                  ] ++ envModule;
                };
              }
            ) hmUsers
          ) manifest.hosts
        );
    };
}
