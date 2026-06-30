{
  self,
  nixpkgs,
  home-manager,
  ...
}@inputs:
rec {
  mkSystems =
    {
      root,
      inputs ? { },
      modules ? [ ],
      overlays ? { },
    }:
    let
      immutableRoot = if inputs ? self then inputs.self else root;
      manifestPath = immutableRoot + "/manifest.toml";
      manifest =
        if builtins.pathExists manifestPath then
          builtins.fromTOML (builtins.readFile manifestPath)
        else
          { };

      getEnabledUsers =
        hostCfg: builtins.filter (u: builtins.elem u.name (hostCfg.users or [ ])) (manifest.users or [ ]);

      # Collect unique input names referenced by a host's enabled users
      getUserInputNames =
        hostCfg:
        nixpkgs.lib.unique (builtins.concatLists (map (u: u.inputs or [ ]) (getEnabledUsers hostCfg)));

      # Auto-import nixosModules.default from user-referenced inputs that export them,
      # but skip flakes that define homeManagerModules (which indicates they are Home Manager env/dotfile flakes).
      getInputNixosModules =
        hostCfg:
        builtins.concatLists (
          map (inputName:
            let inp = inputs.${inputName}; in
            nixpkgs.lib.optional
              (inp ? nixosModules && inp.nixosModules ? default && !(inp ? homeManagerModules))
              inp.nixosModules.default
          ) (getUserInputNames hostCfg)
        );
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
            # Auto-import nixosModules.default from user-referenced input flakes
            ++ getInputNixosModules hostCfg
            ++ nixpkgs.lib.optional (builtins.pathExists (immutableRoot + "/hosts/default.nix")) (
              immutableRoot + "/hosts/default.nix"
            )
            ++ nixpkgs.lib.optional (builtins.pathExists (
              immutableRoot + "/hosts/${hostCfg.name}/default.nix"
            )) (immutableRoot + "/hosts/${hostCfg.name}/default.nix")
            ++ modules;
          };
        }) (manifest.hosts or [ ])
      );
    };

  wrapPackage =
    args@{
      pkgs,
      pkg,
      deps ? [ ],
      env ? { },
    }:
    let
      resolvedDeps = pkgs.lib.concatMap (
        dep:
        if pkgs.lib.isDerivation dep then
          [ dep ]
        else if builtins.isAttrs dep then
          pkgs.lib.mapAttrsToList (
            name: val:
            if pkgs.lib.isDerivation val then
              let
                binName = val.meta.mainProgram or val.pname or (builtins.parseDrvName val.name).name;
              in
              pkgs.writeShellScriptBin name ''
                exec ${val}/bin/${binName} "$@"
              ''
            else if builtins.isList val then
              pkgs.writeShellScriptBin name ''
                exec ${builtins.elemAt val 0}/bin/${builtins.elemAt val 1} "$@"
              ''
            else if builtins.isString val then
              pkgs.writeShellScriptBin name ''
                exec ${val} "$@"
              ''
            else
              throw "wrapPackage: Unsupported mapping target for key '${name}' in deps"
          ) dep
        else
          [ dep ]
      ) deps;

      wrapped = pkgs.symlinkJoin {
        name = "${pkg.pname or pkg.name or "package"}-wrapped";
        paths = [ pkg ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = builtins.replaceStrings [ "\r" ] [ "" ] ''
          for bin in $out/bin/*; do
            if [ -f "$bin" ] && [ -x "$bin" ]; then
              wrapProgram "$bin" \
                ${pkgs.lib.optionalString (resolvedDeps != [ ]) "--prefix PATH : ${pkgs.lib.makeBinPath resolvedDeps}"} \
                ${pkgs.lib.concatStringsSep " " (
                  pkgs.lib.mapAttrsToList (k: v: "--set-default \"${k}\" \"${v}\"") env
                )}
            fi
          done
        '';
      };
    in
    wrapped // (
      pkgs.lib.optionalAttrs (pkg ? override) {
        override = x: wrapPackage (args // { pkg = pkg.override x; });
      }
    ) // (
      pkgs.lib.optionalAttrs (pkg ? overrideAttrs) {
        overrideAttrs = x: wrapPackage (args // { pkg = pkg.overrideAttrs x; });
      }
    );
}
