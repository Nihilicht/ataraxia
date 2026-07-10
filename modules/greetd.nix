{
  pkgs,
  users,
  manifest ? {},
  ...
}: let
  hasDesktop = builtins.any (u: (u.desktop or "") != "") users;
in {
  # Custom login screen using Cage (Kiosk compositor) and Quickshell
  services.greetd = {
    enable = hasDesktop;
    settings = {
      default_session = {
        command = "${pkgs.cage}/bin/cage -s -- sh -c '${pkgs.quickshell}/bin/quickshell -p /etc/greetd/shell.qml > /tmp/quickshell.log 2>&1'";
        user = "greeter";
      };
    };
  };

  # Enable seatd daemon for seat management
  services.seatd.enable = hasDesktop;

  # Ensure the greeter user has permission to access the seat and video hardware
  users.users.greeter =
    if hasDesktop
    then {
      extraGroups = ["seat" "video"];
    }
    else {};

  # Link custom greeter assets and the manifest to the expected greetd path.
  environment.etc =
    if hasDesktop
    then {
      "greetd/shell.qml".source = ../greetd/shell.qml;
      "greetd/assets".source = ../greetd/assets;
      "greetd/manifest.json".text = builtins.toJSON manifest;
    }
    else {};
}
