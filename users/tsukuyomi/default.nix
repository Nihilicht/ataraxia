{
  config,
  pkgs,
  lib,
  userData,
  ...
}:

{
  # Accessing name dynamically from manifest data
  users.users.${userData.name} = {
    shell = pkgs.fish;
  };

  ataraxia.unfreePackages = [
    "antigravity"
  ];

  # Dynamically enable programs listed in the manifest
  programs = builtins.listToAttrs (
    map (prog: {
      name = prog;
      value = {
        enable = true;
      };
    }) (userData.programs or [ ])
  );

  # If you want to use the 'home' boolean from manifest for other system settings
  # networking.extraHosts = if userData.home then "..." else "";
}
