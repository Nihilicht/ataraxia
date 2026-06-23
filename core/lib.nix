{ self, nixpkgs, home-manager, ... }@inputs:
{
  mkSystems =
    {
      root,
      inputs ? { },
      extraModules ? [ ],
      overlays ? { },
    }:
    let
      manifest = builtins.fromTOML (builtins.readFile (root + "/manifest.toml"));

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
            ++ nixpkgs.lib.optional (builtins.pathExists (root + "/modules/default.nix")) (
              root + "/modules/default.nix"
            )
            ++ extraModules;
          };
        }) (manifest.hosts or [ ])
      );
    };

  wrapPackage =
    {
      pkgs,
      pkg,
      deps ? [ ],
      env ? { },
    }:
    pkgs.symlinkJoin {
      name = "${pkg.pname or pkg.name or "package"}-wrapped";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              ${pkgs.lib.optionalString (deps != [ ]) "--prefix PATH : ${pkgs.lib.makeBinPath deps}"} \
              ${pkgs.lib.concatStringsSep " " (pkgs.lib.mapAttrsToList (k: v: "--set \"${k}\" \"${v}\"") env)}
          fi
        done
      '';
    };
}
