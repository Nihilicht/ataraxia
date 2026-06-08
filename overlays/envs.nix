{ inputs, ... }:
{
  # This is only for environment/dotfile flakes
  # The input is 'env' as defined in flake.nix
  tsukuyomi-env = inputs.tsukuyomi-env.overlays.default or (final: prev: { });
}
