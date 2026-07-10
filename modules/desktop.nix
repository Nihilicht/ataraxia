{
  pkgs,
  users,
  ...
}: let
  hasHyprland = builtins.any (u: (u.desktop or "") == "hyprland.desktop") users;
in {
  # Desktop Environment / Window Manager mappings
  programs.hyprland = {
    enable = hasHyprland;
    xwayland.enable = false;
    withUWSM = true;
  };

  xdg.portal = {
    enable = hasHyprland;
    extraPortals = [pkgs.xdg-desktop-portal-gtk];
  };

  # Keyring support
  services.gnome.gnome-keyring.enable = hasHyprland;
  security.pam.services.greetd.enableGnomeKeyring = hasHyprland;
}
