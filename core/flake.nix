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
      lib = {
        mkSystems =
          {
            root,
            inputs ? { },
            extraModules ? [ ],
            overlays ? { },
          }:
          let
            manifest = fromTOML (builtins.readFile (root + "/manifest.toml"));

            getEnabledUsers =
              hostCfg: builtins.filter (u: builtins.elem u.name (hostCfg.users or [ ])) (manifest.users or [ ]);
          in
          {
            nixosConfigurations = builtins.listToAttrs (
              map (hostCfg: {
                name = hostCfg.name;
                value = nixpkgs.lib.nixosSystem {
                  system = hostCfg.arch;
                  specialArgs = {
                    inherit root inputs hostCfg;
                    hostName = hostCfg.name;
                    enabledUsers = getEnabledUsers hostCfg;
                  };
                  modules = [
                    self.nixosModules.default
                    home-manager.nixosModules.home-manager
                    ({ ... }: {
                      nixpkgs.overlays = builtins.attrValues overlays;
                      nix.registry.nixpkgs.flake = nixpkgs;
                    })
                  ]
                  ++ nixpkgs.lib.optional (builtins.pathExists (root + "/hosts/${hostCfg.name}/default.nix")) (
                    root + "/hosts/${hostCfg.name}/default.nix"
                  )
                  ++ nixpkgs.lib.optional (builtins.pathExists (root + "/users/default.nix")) (
                    root + "/users/default.nix"
                  )
                  ++ nixpkgs.lib.optional (builtins.pathExists (root + "/modules/default.nix")) (
                    root + "/modules/default.nix"
                  )
                  ++ extraModules;
                };
              }) (manifest.hosts or [ ])
            );

            homeConfigurations = builtins.listToAttrs (
              builtins.concatMap (
                hostCfg:
                let
                  pkgs = import nixpkgs {
                    system = hostCfg.arch;
                    overlays = builtins.attrValues overlays;
                  };
                  enabledUsers = getEnabledUsers hostCfg;
                  hmUsers = builtins.filter (u: u.home or false) enabledUsers;
                in
                map (
                  user:
                  let
                    userHomeFile = root + "/users/${user.name}/home.nix";
                  in
                  {
                    name = "${user.name}@${hostCfg.name}";
                    value = home-manager.lib.homeManagerConfiguration {
                      inherit pkgs;
                      extraSpecialArgs = {
                        inherit inputs;
                      };
                      modules = [
                        {
                          home.username = user.name;
                          home.homeDirectory = "/home/${user.name}";
                          _module.args.userData = user;
                        }
                      ]
                      ++ nixpkgs.lib.optional (builtins.pathExists userHomeFile) userHomeFile;
                    };
                  }
                ) hmUsers
              ) (manifest.hosts or [ ])
            );
          };
      };
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


      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          root,
          hostCfg,
          enabledUsers,
          ...
        }:
        {
          options.ataraxia.root = lib.mkOption {
            type = lib.types.path;
            default = root;
            readOnly = true;
            description = "Path to the root of the configuration repository";
          };

          options.ataraxia.manifest = lib.mkOption {
            type = lib.types.attrs;
            default =
              if builtins.pathExists (root + "/manifest.toml") then
                fromTOML (builtins.readFile (root + "/manifest.toml"))
              else
                { };
            readOnly = true;
            description = "Parsed content of the manifest.toml file";
          };

          config = {
            assertions = [
              {
                assertion = config.ataraxia.root != null;
                message = "ataraxia.root must be defined.";
              }
              {
                assertion = builtins.pathExists (config.ataraxia.root + "/manifest.toml");
                message = "ataraxia: manifest.toml is required at the root of the configuration repository.";
              }
            ];

            users.users =
              builtins.listToAttrs (
                map (user: {
                  name = user.name;
                  value = {
                    isNormalUser = true;
                    extraGroups = user.groups or [ ];
                    initialPassword = lib.mkDefault "";
                  };
                }) enabledUsers
              )
              // {
                root.initialPassword = lib.mkDefault "";
              };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            environment.systemPackages = [
              self.packages.${pkgs.system}.ataraxia
            ];
          };
        };
    };
}
