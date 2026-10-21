{
  description = "Ataraxia application flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    copyparty = {
      url = "github:9001/copyparty";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
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

    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tsukuyomi-env = {
      url = "github:Nihilicht/tsukuyomi-env";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.helium.follows = "helium";
    };

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    devenv,
    home-manager,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;

    manifest = builtins.fromTOML (builtins.readFile ./manifest.toml);

    hosts = lib.listToAttrs (map (h: {
        name = h.name;
        value = h;
      })
      manifest.hosts);
    users = lib.listToAttrs (map (u: {
        name = u.name;
        value = u;
      })
      manifest.users);

    # Custom symlinkJoin + makeWrapper helper
    wrapPackage = {
      pkgs,
      pkg,
      deps ? [],
    }:
      pkgs.symlinkJoin {
        name =
          if (pkg ? pname && pkg ? version)
          then "${pkg.pname}-${pkg.version}-wrapped"
          else if (pkg ? name)
          then "${pkg.name}-wrapped"
          else "package-wrapped";
        paths = [pkg];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          for bin in $out/bin/*; do
            if [ -f "$bin" ] && [ -x "$bin" ]; then
              wrapProgram "$bin" --prefix PATH : ${pkgs.lib.makeBinPath deps}
            fi
          done
        '';
      };
  in {
    nixosConfigurations =
      lib.mapAttrs (
        hostName: hostCfg:
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = {
              inherit inputs hostCfg manifest;
              users = builtins.attrValues users;
              ataraxia = {
                lib = {
                  inherit wrapPackage;
                };
              };
            };
            modules = [
              ./hosts/${hostName}
              ./hosts/default.nix
              ./modules
              home-manager.nixosModules.home-manager
              inputs.aagl.nixosModules.default
              {
                # Apply overlays
                nixpkgs.overlays = builtins.attrValues (import ./overlays {inherit inputs;});

                # Basic configuration of home-manager
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  extraSpecialArgs = {
                    inherit inputs;
                    ataraxia = {
                      lib = {
                        inherit wrapPackage;
                      };
                    };
                  };
                  sharedModules = [
                    ./users/default.nix
                    inputs.tsukuyomi-env.homeManagerModules.default
                  ];
                  users = lib.genAttrs (hostCfg.users or []) (
                    username: let
                      userCfg = users.${username} or (throw "User ${username} not found in metadata");
                    in
                      {...}: {
                        imports = [./users/${username}/home.nix];
                        _module.args.userData = userCfg;
                      }
                  );
                };

                # Configure NixOS user accounts automatically based on the user metadata
                users.users = lib.genAttrs (hostCfg.users or []) (
                  username: let
                    u = users.${username} or (throw "User ${username} metadata not found");
                  in {
                    isNormalUser = true;
                    extraGroups = (u.groups or []) ++ ["networkmanager"];
                    shell =
                      if (u.shell or "") == "fish"
                      then pkgs.fish
                      else pkgs.bash;
                  }
                );

                # Grant trusted-user privileges to users with trusted = true
                nix.settings.trusted-users = builtins.filter (
                  username: let
                    u = users.${username} or {};
                  in
                    u.trusted or false
                ) (hostCfg.users or []);
              }
            ];
          }
      )
      hosts;

    devShells.${system}.default = devenv.lib.mkShell {
      inherit inputs pkgs;
      modules = [./devenv.nix];
    };
  };
}
