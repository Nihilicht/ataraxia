# Ataraxia Manager (CLI) Design

The `ataraxia` CLI is a Rust-based **Trusted Agent**. Its primary function is to orchestrate the synchronization between the data-driven workspace and the Nix engine while enforcing strict privilege separation.

## The Elevation Strategy: "Dry Run" Evaluation

To avoid unnecessary administrative prompts while maintaining security, the CLI employs a smart "Dry Run" strategy. It evaluates the impact of requested changes before execution.

### Workflow: `ataraxia switch`

1.  **Workspace Discovery & Validation:**
    *   The CLI locates the workspace root by finding `manifest.toml`.
    *   It performs a non-root evaluation to ensure the directory structure matches the manifest definitions.

2.  **The Dry Run (Impact Assessment):**
    *   The CLI executes a non-root Nix evaluation (e.g., `nix build --dry-run` or inspecting the evaluation output).
    *   It analyzes the derivation to determine the scope of changes.

3.  **Smart Execution:**
    *   **User-Level Changes Only:** If the evaluation reveals that changes are strictly isolated to the user's home directory (e.g., dotfiles, user-specific packages managed via Home Manager), the CLI applies the changes silently using standard user privileges.
    *   **System-Level Changes:** If the evaluation detects modifications to system-level derivations (e.g., `/etc/`, system services, or host configurations), the CLI pauses and outputs:
        > `System-level changes detected. Elevation required.`
    *   The CLI then prompts for administrative elevation (via Polkit or `sudo`) to execute the final `nixos-rebuild switch`.

## Transient Git Trust

Because `/etc/ataraxia` is strictly owned by `root` (enforcing the Boundary Mechanism), standard users would normally encounter `libgit2` ownership errors during evaluation.

The CLI bypasses this securely via **Transient Environment Injection**:
*   When spawning the `nix eval` subprocess, the CLI injects `GIT_CONFIG_COUNT` and `safe.directory` environment variables for the workspace path.
*   This grants Nix read-access for that specific evaluation run *without* modifying the user's global `~/.gitconfig` or altering the repository's secure permissions.