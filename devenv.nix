{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  languages.nix.enable = true;

  # Pre-commit hooks for Nix code quality
  git-hooks.hooks = {
    alejandra.enable = true;
    deadnix.enable = true;
    statix.enable = true;
  };

  # Tooling packages available inside the development shell
  packages = with pkgs; [
    alejandra
    deadnix
    statix
  ];

  scripts = {
    "nixos:switch".exec = ''
      host="''${1:-$(hostname)}"
      echo "Rebuilding and switching NixOS configuration for host: $host..."
      sudo nixos-rebuild switch --flake "${config.devenv.root}#$host"
    '';
    "nixos:boot".exec = ''
      host="''${1:-$(hostname)}"
      echo "Rebuilding and setting boot menu configuration for host: $host..."
      sudo nixos-rebuild boot --flake "${config.devenv.root}#$host"
    '';
    "nixos:test".exec = ''
      host="''${1:-$(hostname)}"
      echo "Rebuilding and testing NixOS configuration for host: $host..."
      sudo nixos-rebuild test --flake "${config.devenv.root}#$host"
    '';
    "nixos:build".exec = ''
      host="''${1:-$(hostname)}"
      echo "Building NixOS configuration for host: $host..."
      nix build "${config.devenv.root}#nixosConfigurations.$host.config.system.build.toplevel"
    '';
    "nixos:gc".exec = ''
      echo "Deleting system generations older than 5 days..."
      sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5
      echo "Running garbage collection..."
      nix-store --gc
    '';
    "flake:update".exec = ''
      echo "Updating flake inputs..."
      cd "${config.devenv.root}" && nix flake update
    '';
    "repo:format".exec = ''
      echo "Formatting all Nix files in the repository..."
      alejandra "${config.devenv.root}"
    '';
  };
}
