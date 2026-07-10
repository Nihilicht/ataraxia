{inputs, ...}: final: prev:
(import ../pkgs {
  pkgs = final;
  inputs = inputs;
})
// {
  fjordlauncher =
    inputs.fjordlauncher.packages.${prev.stdenv.hostPlatform.system}.fjordlauncher.override
    {
      fjordlauncher-unwrapped =
        (inputs.fjordlauncher.packages.${prev.stdenv.hostPlatform.system}.fjordlauncher-unwrapped.override {
          extra-cmake-modules = final.kdePackages.extra-cmake-modules;
        }).overrideAttrs
        (old: {
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [final.pkg-config];
        });
    };
  antigravity = inputs.antigravity-nix.packages.${prev.stdenv.hostPlatform.system}.default;
  antigravity-ide = inputs.antigravity-nix.packages.${prev.stdenv.hostPlatform.system}.google-antigravity-ide;
  antigravity-cli = inputs.antigravity-nix.packages.${prev.stdenv.hostPlatform.system}.google-antigravity-cli;
}
