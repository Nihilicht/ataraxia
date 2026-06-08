{ inputs, ... }:
final: prev:
(import ../pkgs { pkgs = final; })
// {
  fjordlauncher =
    inputs.fjordlauncher.packages.${prev.stdenv.hostPlatform.system}.fjordlauncher.override
      {
        fjordlauncher-unwrapped =
          (inputs.fjordlauncher.packages.${prev.stdenv.hostPlatform.system}.fjordlauncher-unwrapped.override {
            extra-cmake-modules = final.kdePackages.extra-cmake-modules;
          }).overrideAttrs
            (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
            });
      };
}
