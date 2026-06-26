{
  self,
  nixpkgs,
  home-manager,
  ...
}@inputs:
{
  config,
  lib,
  pkgs,
  root,
  hostCfg,
  users,
  inputs,
  ...
}:
let
  immutableRoot = if inputs ? self then inputs.self else config.ataraxia.root;
  mutableRoot = config.ataraxia.root;
in
{
  options.ataraxia.root = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = "Path to the root of the configuration repository";
  };

  options.ataraxia.manifest = lib.mkOption {
    type = lib.types.attrs;
    default =
      if builtins.pathExists (immutableRoot + "/manifest.toml") then
        builtins.fromTOML (builtins.readFile (immutableRoot + "/manifest.toml"))
      else
        { };
    readOnly = true;
    description = "Parsed content of the manifest.toml file";
  };

  options.ataraxia.hostCfg = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    description = "Configuration details for the current host";
  };

  options.ataraxia.users = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    readOnly = true;
    description = "List of users enabled on this host";
  };

  config = {
    assertions = [
      {
        assertion = config.ataraxia.root != null;
        message = "ataraxia.root must be defined.";
      }
      {
        assertion = builtins.pathExists (immutableRoot + "/manifest.toml");
        message = "ataraxia: manifest.toml is required at the root of the configuration repository.";
      }
      {
        assertion = root == config.ataraxia.root;
        message = "Ataraxia security boundary violation: root directory argument has been overridden.";
      }
      {
        assertion = hostCfg == config.ataraxia.hostCfg;
        message = "Ataraxia security boundary violation: hostCfg argument has been overridden.";
      }
      {
        assertion = users == config.ataraxia.users;
        message = "Ataraxia security boundary violation: users argument has been overridden.";
      }
      {
        assertion =
          builtins.hasAttr "hosts" config.ataraxia.manifest
          && builtins.hasAttr "users" config.ataraxia.manifest;
        message = "Ataraxia: manifest.toml must define both 'hosts' and 'users' lists.";
      }
      {
        assertion = builtins.elem config.ataraxia.hostCfg.name (
          map (h: h.name) (config.ataraxia.manifest.hosts or [ ])
        );
        message = "Ataraxia: current host '${config.ataraxia.hostCfg.name}' is not registered in manifest.toml.";
      }
      {
        assertion = lib.all (
          uName: builtins.elem uName (map (u: u.name) (config.ataraxia.manifest.users or [ ]))
        ) (config.ataraxia.hostCfg.users or [ ]);
        message = "Ataraxia: one or more users assigned to host '${config.ataraxia.hostCfg.name}' are not registered globally in manifest.toml.";
      }
    ];

    warnings =
      let
        allAssignedUsers = lib.unique (
          builtins.concatLists (map (h: h.users or [ ]) (config.ataraxia.manifest.hosts or [ ]))
        );
        globalUsers = map (u: u.name) (config.ataraxia.manifest.users or [ ]);
        unassignedUsers = builtins.filter (uName: !builtins.elem uName allAssignedUsers) globalUsers;
      in
      map (
        uName:
        "Ataraxia: user '${uName}' is globally registered in manifest.toml but not assigned to any host."
      ) unassignedUsers;

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    programs.git.enable = true;
    programs.git.config.safe.directory = "*";
    security.sudo.extraConfig = ''
      Defaults env_keep += "ATARAXIA_WORKSPACE"
    '';

    programs.fish.enable = lib.mkDefault (builtins.any (u: (u.shell or "") == "fish") users);
    programs.zsh.enable = lib.mkDefault (builtins.any (u: (u.shell or "") == "zsh") users);

    users.users =
      builtins.listToAttrs (
        map (user: {
          name = user.name;
          value = {
            isNormalUser = true;
            createHome = user.desktop or "" != "";
            extraGroups = user.groups or [ ];
            initialPassword = lib.mkDefault "";
            shell =
              if (user.shell or "") == "fish" then
                pkgs.fish
              else if (user.shell or "") == "zsh" then
                pkgs.zsh
              else
                pkgs.bashInteractive;
          };
        }) users
      )
      // {
        root.initialPassword = lib.mkDefault "";
      };
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = {
      ataraxia = self;
    };
    home-manager.users =
      let
        osConfig = config;
      in
      builtins.listToAttrs (
        map (user: {
          name = user.name;
          value =
            let
              userHomeFile = immutableRoot + "/users/${user.name}/home.nix";

              # Only expose nixpkgs + explicitly allowed inputs to this user
              allowedInputNames = [ "nixpkgs" ] ++ (user.inputs or [ ]);
              userInputs = builtins.listToAttrs (
                map (inputName: {
                  name = inputName;
                  value = inputs.${inputName};
                }) allowedInputNames
              );
            in
            {
              config,
              userData ? null,
              inputs ? null,
              ataraxia ? null,
              ...
            }:
            {
              options.ataraxia.user.data = lib.mkOption {
                type = lib.types.attrs;
                readOnly = true;
                description = "Metadata of the current user";
              };
              options.ataraxia.user.inputs = lib.mkOption {
                type = lib.types.attrs;
                readOnly = true;
                description = "Flake inputs accessible by the current user";
              };

              config = {
                ataraxia.user.data = user;
                ataraxia.user.inputs = userInputs;

                assertions = [
                  {
                    assertion = userData != null && userData == config.ataraxia.user.data;
                    message = "Ataraxia security boundary violation: userData argument has been overridden or is missing.";
                  }
                  {
                    assertion = inputs != null && inputs == config.ataraxia.user.inputs;
                    message = "Ataraxia security boundary violation: inputs argument has been overridden or is missing.";
                  }
                ];

                home.username = user.name;
                home.homeDirectory = "/home/${user.name}";
                _module.args.userData = user;
                _module.args.inputs = userInputs;
                home.file.".ataraxia".source =
                  config.lib.file.mkOutOfStoreSymlink "${mutableRoot}/users/${user.name}";
              };
              imports =
                nixpkgs.lib.optional (builtins.pathExists (immutableRoot + "/users/default.nix")) (
                  immutableRoot + "/users/default.nix"
                )
                ++ nixpkgs.lib.optional (builtins.pathExists userHomeFile) userHomeFile;
            };
        }) users
      );

    environment.systemPackages = [
      pkgs.git
      (self.lib.wrapPackage {
        inherit pkgs;
        pkg = self.packages.${pkgs.system}.ataraxia;
        deps = [
          pkgs.git
          pkgs.nix
          home-manager.packages.${pkgs.system}.home-manager
        ];
        env = {
          ATARAXIA_WORKSPACE = mutableRoot;
        };
      })
    ];

    virtualisation.vmVariant = {
      virtualisation.sharedDirectories.ataraxia-workspace = {
        source = mutableRoot;
        target = mutableRoot;
      };
      boot.resumeDevice = lib.mkForce "";
      boot.consoleLogLevel = lib.mkForce 3;
      boot.initrd.systemd.enable = lib.mkForce true;
      boot.initrd.kernelModules = [
        "9p"
        "9pnet_virtio"
      ];
      fileSystems."/boot" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "mode=0755" ];
      };
      swapDevices = lib.mkForce [ ];
      virtualisation.qemu.options = [ "-cpu qemu64" ];
    };
  };
}
