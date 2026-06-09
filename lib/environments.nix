{ lib }:
validEnvs:
lib.mapAttrs
  (name: flake:
    if flake ? homeManagerModules.default then
      flake.homeManagerModules.default
    else
      throw "Environment flake for '${name}' is registered but does not export 'homeManagerModules.default'."
  )
  validEnvs
