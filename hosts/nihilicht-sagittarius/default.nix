{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix # Hardware scan results
  ];

  # Location of the swap partition/file for hibernation/resume.
  boot.resumeDevice = "/dev/disk/by-uuid/34819098-9b4a-4c8a-9274-bfea8f0df233";

  # Shared NTFS partition for interoperability with Windows.
  fileSystems."/mnt/shared" = {
    device = "/dev/disk/by-uuid/66C27368BA402D04";
    fsType = "ntfs3";
    options = [
      "rw"
      "uid=1000"
      "gid=100"
      "dmask=022"
      "fmask=133"
      "nofail" # Don't hang boot if the drive is missing
      "force" # Ignore minor Windows metadata flags
      "noauto"
      "x-systemd.automount" # Mount only when accessed
      "x-systemd.idle-timeout=60" # Unmount after 1 minute of inactivity
    ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's NOT the version of your packages.
  # DO NOT CHANGE unless you have read the documentation for it.
  system.stateVersion = "26.05";
}
