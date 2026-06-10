{
  config,
  lib,
  pkgs,
  hostName,
  hostCfg,
  ...
}:

{
  options.ataraxia.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "List of unfree packages to allow system-wide.";
  };

  config = {
    networking.hostName = hostName;

    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) (
        [
          "steam-unwrapped"
          "cloudflare-warp"
        ]
        ++ config.ataraxia.unfreePackages
      );

    # Enforce root-only permissions globally, but give users control of their own folders
  system.activationScripts.enforceAtaraxiaPerms = ''
    if [ ! -d "/etc/ataraxia" ]; then
      echo "CRITICAL ERROR: Ataraxia repository must be located at /etc/ataraxia!" >&2
      exit 1
    fi

    # 1. Lock everything down to root by default
    chown -R root:root /etc/ataraxia
    chmod 644 /etc/ataraxia/manifest.toml

    # 2. Give users ownership of their personal configuration folders
    if [ -d "/etc/ataraxia/users" ]; then
      for user_dir in /etc/ataraxia/users/*/; do
        # Skip if the glob didn't match any directories
        [ -d "$user_dir" ] || continue
        
        user_name=$(basename "$user_dir")
        # Check if the user actually exists on the system
        if id "$user_name" >/dev/null 2>&1; then
          chown -R "$user_name:users" "$user_dir"
        fi
      done
    fi
  '';

  boot = {
    # Use the systemd-boot EFI boot loader.
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Always use the latest kernel for better hardware support (especially on AMD).
    kernelPackages = pkgs.linuxPackages_latest;

    # Enable NTFS support for the shared Windows/Data drive.
    supportedFilesystems = [ "ntfs3" ];
  };

  time = {
    # Set the local time zone.
    timeZone = hostCfg.timezone or "UTC";
    # Fix dual-boot time conflicts with Windows (which expects local time).
    #hardwareClockInLocalTime = true;
  };

  networking = {
    # Configure network connections interactively (nmcli/nmtui).
    networkmanager.enable = true;

    # Firewall settings to allow local network communication.
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ]; # SSH access from other devices.
      # UDP 5353 is now handled automatically by services.avahi.openFirewall
    };

    nameservers = hostCfg.nameservers or [
      "1.1.1.1"
      "1.0.0.1"
    ];
  };

  nix = {
    settings = {
      # Enable Flakes and the new 'nix' command line tool.
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Allow the user to perform administrative Nix tasks without sudo.
      trusted-users = [
        "root"
        "@wheel"
      ];
      # Deduplicate files in the store automatically during builds
      auto-optimise-store = true;

      substituters = [ "https://ezkea.cachix.org" ];
      trusted-public-keys = [ "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI=" ];
    };
    # Automatically trigger garbage collection weekly
    gc = {
      automatic = true;
      dates = "weekly";
      # Keep the last 7 days of generations so you can still roll back if needed
      options = "--delete-older-than 7d";
    };
  };

  services = {
    # Keep system time accurately synced.
    ntp.enable = true;

    # Secure remote access configuration.
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = true; # Consider changing to keys-only in the future.
        KbdInteractiveAuthentication = false;
      };
    };

    # Enable mDNS (Avahi) so the machine can be reached via hostname.local
    # This allows you to SSH into the machine without knowing its IP address.
    avahi = {
      enable = true;
      nssmdns4 = true; # Allows the desktop to resolve other .local names
      openFirewall = true; # Automatically opens the correct ports

      ipv4 = true;
      ipv6 = false; # Stops the constant IP flapping collisions

      publish = {
        enable = true;
        addresses = true;
        workstation = true;
        userServices = true; # Broadcast even more service metadata
      };
    };

    # Custom login screen using Cage (Kiosk compositor) and Quickshell.
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.cage}/bin/cage -s -- sh -c '${pkgs.quickshell}/bin/quickshell -p /etc/greetd/shell.qml > /tmp/quickshell.log 2>&1'";
          user = "greeter";
        };
      };
    };

    # Explicitly disable X11 as we are using a Wayland-native setup (Hyprland).
    xserver.enable = false;

    netbird.enable = true;

    cloudflare-warp.enable = true;
  };

  # Link custom greeter assets and the manifest to the expected greetd path.
  environment.etc = {
    "greetd/shell.qml".source = ../greetd/shell.qml;
    "greetd/assets".source = ../greetd/assets;
    "greetd/manifest.json".text = builtins.toJSON (fromTOML (builtins.readFile ../manifest.toml));
  };
};
}
