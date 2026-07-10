# package.nix
{
  pkgs,
  lib,
  fetchzip,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}: let
  hacks = pkgs.callPackage pyproject-nix.build.hacks {};
  # 1. Download and unpack the release asset
  src = fetchzip {
    url = "https://github.com/langchain-ai/deepagents/releases/download/deepagents-code%3D%3D0.1.32/deepagents_code-0.1.32.tar.gz";
    hash = "sha256-LOXR+rYVFJe/OCV8syQ6ZwK1hrreS6x76d7TSW0i1+0="; # Run nix build and copy the generated hash
  };

  # 2. Load the workspace
  workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = src;};

  # 3. Translate uv.lock dependencies
  uvOverlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  # 4. Target Python version
  python = pkgs.python311;

  # 5. Define custom overlays to resolve build-system constraints and relative-path workspace bugs
  pyprojectOverrides = final: prev: {
    # Fix 1: Inject setuptools to build legacy packages
    forbiddenfruit = prev.forbiddenfruit.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.setuptools
        ];
    });

    # Fix 2: Redirect the sibling 'deepagents' SDK to compile from its PyPI release
    deepagents = prev.deepagents.overrideAttrs (old: {
      src = pkgs.fetchPypi {
        pname = "deepagents";
        version = "0.6.12";
        hash = "sha256-HygcC8WmMTL2Li7jRcHcWTsjGI2m4jAWQB9oefvlS18=";
      };
      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail "setuptools>=82.0.1" "setuptools"
      '';
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.setuptools
        ];
    });

    # Fix 3: Redirect partner workspace packages to compile from their PyPI releases
    # This prevents sandbox violations from relative "../partners/..." paths
    langchain-daytona = prev.langchain-daytona.overrideAttrs (old: {
      src = pkgs.fetchPypi {
        pname = "langchain_daytona";
        version = "0.0.7"; # Locked version in uv.lock
        hash = "sha256-f676zj/kKkeZknpjGhQvCBUP7zcQuikpkxKhUBoZ4lg="; # Replace with correct hash on build mismatch
      };
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.hatchling
          final.pathspec
          final.pluggy
          final.trove-classifiers
        ];
    });

    langchain-modal = prev.langchain-modal.overrideAttrs (old: {
      src = pkgs.fetchPypi {
        pname = "langchain_modal";
        version = "0.0.5";
        hash = "sha256-rNPuFiZK2X0AQPILfHEZSM+Qu/H9eR6e/98r48gvOL8=";
      };
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.hatchling
          final.pathspec
          final.pluggy
          final.trove-classifiers
        ];
    });

    langchain-runloop = prev.langchain-runloop.overrideAttrs (old: {
      src = pkgs.fetchPypi {
        pname = "langchain_runloop";
        version = "0.0.6"; # Adjust to 0.0.5 if your specific uv.lock specifies it
        hash = "sha256-2NlH6EfoM6tZLqj6wRLCtvbtnhan2hkf0WPAvojg7fM=";
      };
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.hatchling
          final.pathspec
          final.pluggy
          final.trove-classifiers
        ];
    });

    langchain-vercel-sandbox = prev.langchain-vercel-sandbox.overrideAttrs (old: {
      src = pkgs.fetchPypi {
        pname = "langchain_vercel_sandbox";
        version = "0.0.1";
        hash = "sha256-ugzkz5yAzck0UMOxtkFFkc75uEKkm5oS0pqjwfaX0j8=";
      };
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.hatchling
          final.pathspec
          final.pluggy
          final.trove-classifiers
        ];
    });

    langchain-quickjs = prev.langchain-quickjs.overrideAttrs (old: {
      src = pkgs.fetchPypi {
        pname = "langchain_quickjs";
        version = "0.3.2";
        hash = "sha256-YcBUbGboXYYPvuJVFwHGidsjwj/EZlPXbyikPKMHTZY=";
      };
      nativeBuildInputs =
        (old.nativeBuildInputs or [])
        ++ [
          final.hatchling
          final.pathspec
          final.pluggy
          final.trove-classifiers
        ];
    });

    wasmtime = hacks.nixpkgsPrebuilt {
      from = python.pkgs.wasmtime;
      prev = prev.wasmtime;
    };
  };

  # 6. Compose your environment with our fixes overlay included
  pythonSet = (pkgs.callPackage pyproject-nix.build.packages {inherit python;})
    .overrideScope (lib.composeManyExtensions [
    pyproject-build-systems.overlays.default
    uvOverlay
    pyprojectOverrides # Redirects all partner integrations to PyPI
  ]);
in
  # 7. Compile the virtualenv
  pythonSet.mkVirtualEnv "dcode-env" workspace.deps.default
