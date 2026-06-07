{ config, pkgs, enabledUsers, ... }:

{
  imports = map (user: (
    { ... }: {
      _file = ./${user.name}/default.nix;
      imports = [ (import ./${user.name}/default.nix) ];
      _module.args.userData = user;
    }
  )) enabledUsers;

  # Basic account properties
  users.users = builtins.listToAttrs (map (user: {
    name = user.name;
    value = {
      isNormalUser = true;
      extraGroups = user.groups or [ ];
    };
  }) enabledUsers);

  # Home Manager integration
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users = builtins.listToAttrs (map (user: {
      name = user.name;
      value = { ... }: {
        imports = [ ./${user.name}/home.nix ];
        home.username = user.name;
        home.homeDirectory = "/home/${user.name}";
        programs.home-manager.enable = true;
        _module.args.userData = user;
      };
    }) (builtins.filter (u: u.home or false) enabledUsers));
  };
}
