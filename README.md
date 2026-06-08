# Ataraxia

Ataraxia is a highly modular, secure, and dynamically provisioned NixOS & Home Manager configuration flake. Built with strict sandboxing and developer experience in mind.

## ✨ Capabilities

### 1. Dynamic Environment Binding
Instead of hardcoding user configurations inside monolithic `home.nix` files, Ataraxia utilizes a declarative `manifest.toml` to dynamically map system users to specific environment flakes. The system automatically searches for explicitly registered environments (e.g., `tsukuyomi-env`) and binds them directly into the target user's Home Manager configuration. 

This provides fail-safe validation: if a requested environment is missing or unused, the Nix evaluator will warn you before the build finishes.

### 2. Hermetic Dependency Isolation (`wrapWithDeps`)
Ataraxia features a powerful dependency sandboxing library function: `nixataraxia.wrapWithDeps`.
This utility wraps binaries to execute with a localized `PATH` containing specific dependencies, preventing global scope pollution.
- **Example**: The `helix` text editor is injected with `nixd` and `lua-language-server`.
- **Example**: `imagemagick` is injected with `libraw` for RAW photo processing.
Neither of these dependencies leak into the user's primary terminal autocomplete or system `PATH`.

### 3. Strict Permission Sandboxing
To ensure operational security, Ataraxia enforces stringent file-ownership mechanisms via NixOS activation scripts:
- Global configurations (`/etc/ataraxia/manifest.toml`, core flakes) are heavily restricted to `root:root`.
- User-specific dotfiles within `/etc/ataraxia/users/*/` are automatically `chown`'d to their respective owners (`username:users`), enabling permissionless live-editing of personal user configs without risking system integrity.

### 4. Modular User Tooling
Home Manager configs are strictly categorized by domain, allowing easy toggling of toolchains:
- `apps.nix`: Core desktop applications and browsers.
- `cli.nix`: Command-line tools, shells (Fish/Starship), and CLI agents.
- `desktop.nix`: Wayland/Hyprland ecosystem tooling (Rofi, Grim, Satty).
- `dev.nix`: Compilers, language servers, and Git configurations.
- `media.nix`: Creative workflows and OBS Studio.

## 🚀 Usage

### Defining Users
All system users and their environments are driven by the `manifest.toml` file at the root of the repository:

```toml
[[users]]
name = "tsukuyomi"
home = true
groups = ["wheel"]
desktop = "hyprland"
environment = "tsukuyomi"
```

When you define a user here, Ataraxia will:
1. Provision the system user and assign groups.
2. Match the `environment` string to registered environment flakes.
3. Automatically enable and import the Home Manager modules.

### The Environment Protocol
To add a completely new dotfile/environment flake into the system:

1. **Add the flake input** in `flake.nix`:
   ```nix
   inputs.alice-env.url = "github:alice/dotfiles";
   ```
2. **Register it** in the `validEnvInputs` array inside `users/default.nix`:
   ```nix
   validEnvInputs = [
     "tsukuyomi-env"
     "alice-env"
   ];
   ```
3. **Assign it** to a user in `manifest.toml`:
   ```toml
   environment = "alice"
   ```

#### Flake Requirements
For the system to successfully consume your environment flake, it **must** export a Home Manager module at `homeManagerModules.default`. 

```nix
# Inside the external environment's flake.nix
outputs = { self, nixpkgs, ... }: {
  homeManagerModules.default = { config, lib, pkgs, nixataraxia, userData, ... }: {
    # Your Home Manager configuration here
  };
};
```

Your module will automatically receive the following `extraSpecialArgs` from Ataraxia:
- `nixataraxia`: The dependency isolation library (e.g., for `nixataraxia.wrapWithDeps`).
- `userData`: The specific user's block from `manifest.toml` (contains their name, groups, desktop, etc.).
- `inputs`: The core system's flake inputs.

The system will automatically validate the binding and import the flake's Home Manager modules.

### Adding Isolated Packages
To add a package with hermetically sealed dependencies, use the injected `nixataraxia` library within any user module:

```nix
{ pkgs, nixataraxia, ... }:

{
  home.packages = [
    (nixataraxia.wrapWithDeps {
      package = pkgs.some-editor;
      deps = [ pkgs.some-lsp ];
    })
  ];
}
```
