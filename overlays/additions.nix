{inputs, ...}: final: prev:
(import ../pkgs {
  pkgs = final;
  inherit inputs;
})
// {
  fjordlauncher =
    inputs.fjordlauncher.packages.${prev.stdenv.hostPlatform.system}.fjordlauncher;
  antigravity = inputs.antigravity-nix.packages.${prev.stdenv.hostPlatform.system}.default;
  antigravity-ide = inputs.antigravity-nix.packages.${prev.stdenv.hostPlatform.system}.google-antigravity-ide;
  antigravity-cli = inputs.antigravity-nix.packages.${prev.stdenv.hostPlatform.system}.google-antigravity-cli;
}
