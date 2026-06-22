# Ataraxia Assertions (Boundary Enforcement)

Ataraxia relies on custom Nix assertions to enforce structural integrity and security boundaries. While standard NixOS and Home Manager isolate configuration options, Ataraxia assertions prevent users from violating the framework's overarching design principles.

## The Role of Assertions
Assertions act as the "Gatekeeper" during the Nix evaluation phase. Before any system or user configuration is realized, the Ataraxia Engine evaluates these rules. If an assertion fails, the build halts immediately, providing a clear error message explaining the policy violation.

## Core Assertion Categories

### 1. Identity Assertions (Authentication)
These ensure that only authorized configurations are evaluated.
* **Manifest Registration:** Asserts that any user configuration being evaluated belongs to a user explicitly registered in `manifest.toml`. Unregistered profiles are rejected.
* **Host Assignment:** Asserts that a user profile is only evaluated for hosts they are assigned to in the manifest.

### 2. Boundary Assertions (The Sandbox)
These prevent users from referencing or importing files outside their designated domain, enforcing strict privilege separation.
* **Import Isolation:** Asserts that files within `users/<username>/` cannot import paths from `hosts/` or other users' directories. This is typically achieved by verifying that the absolute paths of all imports fall within the allowed `${ataraxiaWorkspace}/users/<username>/` prefix.
* **Engine Protection:** Asserts that user modules cannot override or redefine core Ataraxia Engine variables or logic.

### 3. Capability Assertions (System Constraints)
These ensure that user requests (`desktop-shell` configurations) are compatible with the host system's capabilities.
* **Hardware/Protocol Matches:** For example, if a user enables a Wayland-based `desktop-shell`, the engine asserts that the host configuration has Wayland enabled. If not, the build fails safely rather than resulting in a broken system state.

## Implementation Strategy
Assertions are defined within the `ataraxia-core` library. They are injected into both the NixOS (system) evaluation and the Home Manager (user) evaluation via modules, ensuring comprehensive coverage across all layers of the framework.