{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  time.timeZone = "Asia/Manila";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  # Location of the swap partition/file for hibernation/resume.
  boot.resumeDevice = "/dev/disk/by-uuid/34819098-9b4a-4c8a-9274-bfea8f0df233";

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernel.sysctl."vm.swappiness" = 10;
  boot.supportedFilesystems = ["ntfs3"];

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

  boot.loader.systemd-boot.enable = true;
  # Keep only the newest generation's kernel/initrd in the 100M ESP
  boot.loader.systemd-boot.configurationLimit = 1;
  boot.loader.efi.canTouchEfiVariables = true;

  systemd.services.disk-monitor = {
    description = "Lightweight storage and mount state monitor";
    wantedBy = ["multi-user.target"];

    # Provide the exact packages containing mount, df, grep, and dmesg
    path = with pkgs; [
      util-linux # contains: mount, dmesg
      coreutils # contains: df, sleep, date
      gnugrep # contains: grep
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
    };

    script = ''
      while true; do
        echo "=== Telemetry Mark: $(date -u) ==="
        mount | grep "on / "
        df -h /
        df -i /
        dmesg | tail -n 15
        sleep 10
      done
    '';
  };
}
