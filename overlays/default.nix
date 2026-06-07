{ inputs, ... }:
let
  envs = import ./envs.nix { inherit inputs; };
in
{
  # 1. External App Overlays (Direct from inputs)
  aagl = inputs.aagl.overlays.default;
  helium = inputs.helium.overlays.default;

  # 2. Environment/Dotfile Overlays (From envs.nix)
  inherit (envs) tsukuyomi-env;

  # 3. Local custom packages
  additions = import ./additions.nix;

  # 4. Modifications/Overrides
  modifications = import ./modifications.nix;
}
