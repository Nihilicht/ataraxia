{ self, nixpkgs, home-manager, ... }@inputs:
{
  config,
  lib,
  pkgs,
  root,
  hostCfg,
  enabledUsers,
  inputs,
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
        builtins.fromTOML (builtins.readFile (root + "/manifest.toml"))
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
    home-manager.users = let
      osConfig = config;
    in builtins.listToAttrs (
      map (user: {
        name = user.name;
        value = let
          userHomeFile = root + "/users/${user.name}/home.nix";

          # Only expose nixpkgs + explicitly allowed inputs to this user
          allowedInputNames = [ "nixpkgs" ] ++ (user.inputs or [ ]);
          userInputs = builtins.listToAttrs (
            map (inputName: {
              name = inputName;
              value = inputs.${inputName};
            }) allowedInputNames
          );
        in
        { config, ... }:
        {
          imports = [
            {
              home.username = user.name;
              home.homeDirectory = "/home/${user.name}";
              _module.args.userData = user;
              _module.args.inputs = userInputs;
              home.file.".ataraxia".source = config.lib.file.mkOutOfStoreSymlink "${toString osConfig.ataraxia.root}/users/${user.name}";
            }
          ] ++ nixpkgs.lib.optional (builtins.pathExists userHomeFile) userHomeFile;
        };
      }) (builtins.filter (u: u.home or false) enabledUsers)
    );

    environment.systemPackages = [
      (self.lib.wrapPackage {
        inherit pkgs;
        pkg = self.packages.${pkgs.system}.ataraxia;
        env = {
          ATARAXIA_WORKSPACE = "${config.ataraxia.root}";
        };
      })
    ];
  };
}
