{
  config,
  pkgs,
  enabledUsers,
  nixataraxia,
  inputs,
  environments,
  ...
}:

{
  imports = map (
    user:
    (
      { ... }:
      {
        _file = ./${user.name}/default.nix;
        imports = [ (import ./${user.name}/default.nix) ];
        _module.args.userData = user;
      }
    )
  ) enabledUsers;

  # Basic account properties
  users.users = builtins.listToAttrs (
    map (user: {
      name = user.name;
      value = {
        isNormalUser = true;
        extraGroups = user.groups or [ ];
      };
    }) enabledUsers
  );

  # Home Manager integration
  home-manager =
    let
      # Logic to warn about unused environments
      usedEnvs = map (u: u.environment or "") enabledUsers;
      unusedEnvs = builtins.filter (e: !(builtins.elem e usedEnvs)) (builtins.attrNames environments);
      warnUnused =
        if unusedEnvs != [ ] then
          pkgs.lib.warn "Notice: The following environments are listed in extraSpecialArgs but are NOT used by any user: ${builtins.concatStringsSep ", " unusedEnvs}"
        else
          x: x;
    in
    warnUnused {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {
        nixataraxia = nixataraxia {
          inherit pkgs;
          lib = pkgs.lib;
        };
        inherit inputs environments;
      };
      users = builtins.listToAttrs (
        map (
          user:
          let
            envName = user.environment or "";
            isValidEnv = builtins.hasAttr envName environments;

            # Logic to warn if user requests an invalid environment
            warnInvalid =
              if envName != "" && !isValidEnv then
                pkgs.lib.warn "Warning: Environment '${envName}' requested by user '${user.name}' in manifest.toml but not found in environments list!"
              else
                x: x;

            envModule = if isValidEnv then [ environments.${envName} ] else [ ];
          in
          warnInvalid {
            name = user.name;
            value =
              { config, ... }:
              {
                imports = [ ./${user.name}/home.nix ] ++ envModule;
                home.username = user.name;
                home.homeDirectory = "/home/${user.name}";
                home.file.".ataraxia".source = config.lib.file.mkOutOfStoreSymlink "/etc/ataraxia/users/${user.name}";
                _module.args.userData = user;
                env.enable = isValidEnv;
              };
          }
        ) (builtins.filter (u: u.home or false) enabledUsers)
      );
    };
}
