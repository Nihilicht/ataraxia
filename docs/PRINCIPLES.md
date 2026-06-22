# Ataraxia: Core Design Principles

The primary design principle of the Ataraxia framework is the **strict separation of access levels between the User and the System**.

Ataraxia is designed to allow users to configure their own environments freely, while ensuring that the system-level configuration remains secured and isolated from user-level actions.

## 1. The Root Domain (System Level)
System-wide configurations and identity definitions are inherently unsafe for standard users to modify. Therefore, they are strictly controlled at the root level.

*   **The Manifest (`manifest.toml`)**: This file dictates the structure of the fleet (which hosts exist, which users are created, and which environments are assigned). It is owned and managed exclusively by `root`. A user cannot independently alter their assigned environment or create new accounts.
*   **Host Configurations (`hosts/`)**: Hardware definitions and system-level services are restricted to administrators.

## 2. The Boundary Mechanism
Ataraxia relies on **Linux File Permissions** to enforce boundaries within the configuration repository itself.
*   The root repository (e.g., `/etc/ataraxia`) and the core engine files are owned by `root`.
*   User-specific directories (`users/<username>/`) are `chown`'d to the respective user, creating a secure sandbox within the larger framework.

## 3. The User Domain
Users are granted autonomy within their designated boundaries, provided their actions cannot affect the broader system.
*   **User Modules**: Users can write their own Nix modules inside their designated `users/<username>/` directory.
*   **Scope Limitation**: These modules are restricted to configuring user-level applications, dotfiles, and interface elements that are guaranteed not to interact with or compromise system-level services.

## 4. The CLI Bridge
The `ataraxia` manager acts as the mediator between the user's intent and the system's enforcement.
*   When a standard user runs `ataraxia switch`, the CLI evaluates the configuration.
*   If the changes are contained within the User Domain (e.g., updating a dotfile or user module), the switch proceeds.
*   If the switch requires applying changes to the System Level, the CLI will **prompt for elevation** (e.g., requesting an administrator password) before executing the final `nixos-rebuild switch`.
