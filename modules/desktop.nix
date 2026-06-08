{
  config,
  pkgs,
  enabledUsers,
  ...
}:

let
  # Check if any user on this host wants Hyprland
  hasHyprland = builtins.any (u: (u.desktop or "") == "hyprland") enabledUsers;
in
{
  programs.hyprland = {
    enable = hasHyprland;
    xwayland.enable = false; # Pure Wayland setup for performance and security.
    withUWSM = true; # Universal Wayland Session Manager for better session handling.
  };

  # Required for screen sharing, file pickers, and opening links in Wayland.
  xdg.portal = {
    enable = hasHyprland;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
