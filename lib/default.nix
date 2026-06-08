{ pkgs, lib, ... }:

{
  # Section 3: Dependency Isolation & Sandboxing
  # Higher-Order Wrapper Function
  # Isolates dependencies by prepending them to the execution PATH of the target package.
  wrapWithDeps =
    {
      package,
      deps ? [ ],
    }:
    let
      binPath = lib.makeBinPath deps;
    in
    pkgs.symlinkJoin {
      name = "${package.name}-wrapped";
      paths = [ package ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        if [ -d $out/bin ]; then
          for bin in $out/bin/*; do
            if [ -x "$bin" ]; then
              wrapProgram "$bin" --prefix PATH : "${binPath}"
            fi
          done
        fi
      '';
    };
}
