{ pkgs, hostCfg, ... }:
{
  networking.hostName = hostCfg.name;
  time.timeZone = hostCfg.timezone or "UTC";
  i18n.defaultLocale = hostCfg.locale or "en_US.UTF-8";

  # Setup system-level essentials
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  system.stateVersion = "23.11";
}
