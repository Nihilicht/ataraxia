{ pkgs, ... }:

pkgs.rustPlatform.buildRustPackage {
  pname = "ataraxia-cli";
  version = "0.1.0";

  # This points to the manager directory at the root of your project
  src = ../../manager;

  cargoLock = {
    lockFile = ../../manager/Cargo.lock;
  };

  # Since it's a local project, we might need to handle the cargo lock differently
  # or provide a hash if it were remote. For local, lockFile works best.

  meta = {
    description = "Nix configuration manager for Ataraxia";
    mainProgram = "ataraxia";
  };
}
