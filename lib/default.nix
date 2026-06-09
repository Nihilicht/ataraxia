{ pkgs, lib, ... }:

{
  # Section 3: Dependency Isolation & Sandboxing
  # Higher-Order Wrapper Function
  # Isolates dependencies by prepending them to the execution PATH of the target package.
  wrapWithDeps =
    {
      package,
      deps ? [ ],
      extraWrapperArgs ? [ ],
    }:
    let
      binPath = lib.makeBinPath deps;
    in
    pkgs.symlinkJoin {
      name = "${package.name}-wrapped";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        if [ -d $out/bin ]; then
          for bin in $out/bin/*; do
            # Skip if it's not a file or not executable
            if [ -f "$bin" ] && [ -x "$bin" ]; then
              wrapProgram "$bin" \
                --prefix PATH : "${binPath}" \
                ${lib.escapeShellArgs extraWrapperArgs}
            fi
          done
        fi
      '';
    };
}
