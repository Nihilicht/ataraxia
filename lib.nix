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
      immutableRoot = if inputs ? self then inputs.self else root;
      manifest = builtins.fromTOML (builtins.readFile (immutableRoot + "/manifest.toml"));

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
              users = getEnabledUsers hostCfg;
              ataraxia = self;
            };
            modules = [
              self.nixosModules.default
              home-manager.nixosModules.home-manager
              ({ ... }: {
                nixpkgs.overlays = builtins.attrValues overlays;
                nix.registry.nixpkgs.flake = nixpkgs;
                ataraxia.root = root;
                ataraxia.hostCfg = hostCfg;
                ataraxia.users = getEnabledUsers hostCfg;
              })
            ]
            ++ nixpkgs.lib.optional (builtins.pathExists (immutableRoot + "/hosts/${hostCfg.name}/default.nix")) (
              immutableRoot + "/hosts/${hostCfg.name}/default.nix"
            )
            ++ nixpkgs.lib.optional (builtins.pathExists (immutableRoot + "/modules/default.nix")) (
              immutableRoot + "/modules/default.nix"
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
      postBuild = builtins.replaceStrings [ "\r" ] [ "" ] ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              ${pkgs.lib.optionalString (deps != [ ]) "--prefix PATH : ${pkgs.lib.makeBinPath deps}"} \
              ${pkgs.lib.concatStringsSep " " (pkgs.lib.mapAttrsToList (k: v: "--set-default \"${k}\" \"${v}\"") env)}
          fi
        done
      '';
    };
}
