{
  lib,
  hostCfg,
  pkgs,
  ...
}: {
  # Default timezone and locale (downstream can override)
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # Default network configurations
  networking.useDHCP = lib.mkDefault true;
  networking.hostName = lib.mkDefault hostCfg.name;

  # Default system state version
  system.stateVersion = lib.mkDefault "26.05";

  # Allow only specific unfree packages securely
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "steam-unwrapped"
      "cloudflare-warp"
      "obsidian"
      "lmstudio"
    ];

  # Network configurations
  networking = {
    networkmanager = {
      enable = true;
      dns = "none";
    };
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];
  };

  # Global Nix settings
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    substituters = ["https://ezkea.cachix.org"];
    trusted-public-keys = ["ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="];
  };

  # Global program enablement
  programs.git.enable = true;
  programs.fish.enable = true;

  # Host services
  services = {
    # Keep system time accurately synced
    ntp.enable = true;

    # Enable mDNS (Avahi) for local network host resolution
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      ipv4 = true;
      ipv6 = false;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
        userServices = true;
      };
    };

    # VPN and tunneling services
    netbird.enable = true;
    cloudflare-warp.enable = true;
  };

  # Default VM variant resource allocation (downstream can override)
  virtualisation.vmVariant = {
    virtualisation.cores = lib.mkDefault 8;
    virtualisation.memorySize = lib.mkDefault 16384;
    virtualisation.sharedDirectories = {
      ataraxia = {
        source = "/etc/ataraxia";
        target = "/etc/ataraxia";
      };
    };
    virtualisation.forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    # Enable SSH and allow empty password login inside the VM
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
        PermitEmptyPasswords = true;
      };
    };

    security.pam.services.sshd.allowNullPassword = true;
    security.pam.services.login.allowNullPassword = true;

    users.users =
      lib.genAttrs (hostCfg.users or ["tsukuyomi"]) (name: {
        initialHashedPassword = lib.mkForce "";
      })
      // {
        root.initialHashedPassword = lib.mkForce "";
      };

    # VM specific boot and device overrides
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
      options = ["mode=0755"];
    };
    swapDevices = lib.mkForce [];
    virtualisation.qemu.options = ["-cpu qemu64"];
  };
}
