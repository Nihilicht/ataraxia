# Ataraxia — Design Decisions Record

**Last updated**: 2026-06-22  
**Status**: Living document — records all design decisions made through architectural review.

---

## Table of Contents

1. [Target Resolution & Switching Semantics](#1-target-resolution--switching-semantics)
2. [Authentication & Elevation Model](#2-authentication--elevation-model)
3. [Home Manager Integration](#3-home-manager-integration)
4. [Manifest Schema & CLI Surface](#4-manifest-schema--cli-surface)
5. [Import Isolation (Boundary Enforcement)](#5-import-isolation-boundary-enforcement)
6. [Elevation Strategy (Dry-Run Scoping)](#6-elevation-strategy-dry-run-scoping)
7. [File Permission Enforcement](#7-file-permission-enforcement)
8. [State Version Handling](#8-state-version-handling)
9. [Workspace Discovery](#9-workspace-discovery)
10. [Dirty Tracking & Manifest Persistence](#10-dirty-tracking--manifest-persistence)
11. [Uncommitted Changes Check](#11-uncommitted-changes-check)
12. [Project Structure & Lifecycle](#12-project-structure--lifecycle)
13. [Scope Boundaries (What Ataraxia Is Not)](#13-scope-boundaries-what-ataraxia-is-not)

---

## 1. Target Resolution & Switching Semantics

### Decision

The CLI uses a `[user]@[host]` target syntax with intelligent defaults. Empty components resolve to the current environment.

### Resolution Rules

| Input | Resolved Host | Resolved User(s) | Meaning |
|---|---|---|---|
| *(empty)* | Current hostname | Current `$USER` | Switch current user on current host |
| `myhost` | `myhost` | Current `$USER` | Switch current user on named host |
| `@` | Current hostname | All users assigned to host | **System-wide switch** of current host |
| `alice@myhost` | `myhost` | `alice` | Switch only alice on myhost |
| `alice@` | Current hostname | `alice` | Switch only alice on current host |
| `@myhost` | `myhost` | All users assigned to `myhost` | **System-wide switch** of named host |

### Key Semantics

- **`@` (bare at-sign)**: Means "current user on current host" — a system-wide switch scoped to the current identity.
- **`alice@` where alice == `$USER`**: Equivalent to switching the current user. **No authentication required.**
- **Multiple targets on the same host are merged** into a single `ResolvedTarget`.
- **Multiple distinct hosts are rejected** — Ataraxia manages a single device at a time.
- These degenerate inputs are **intentional**, not bugs. The `Target::from_str` is infallible by design.

### Rationale

A host is a device's identity. A single device may have multiple host definitions in the manifest (e.g., for identity switching), but only one applies at a time. Remote fleet deployment is out of scope.

---

## 2. Authentication & Elevation Model

### Decision

The CLI auto-elevates like `paru` — if root privileges are needed and the process is not already root, it re-executes itself with `sudo`.

### Privilege Matrix

| Scenario | Auth Required | Mechanism |
|---|---|---|
| Switch current user's HM config only | **None** | Direct `home-manager switch` |
| Switch a different user's HM config | **Target user's password or root** | `sudo -u <target>` or `sudo` |
| Switch system-level (nixos-rebuild) | **Root** | Auto-elevate via `sudo` |
| `ataraxia hosts list`, `users list`, `check` | **None** | Read-only operations |

### Auto-Elevation Behavior

When a system-level switch is required and the process is not root:

```text
$ ataraxia switch
System-level changes detected. Elevating...
[sudo] password for tsukuyomi: ▮
```

The CLI re-invokes itself with `sudo`, preserving all original arguments. This mirrors how `paru` handles pacman operations that need root.

Instead of re-executing the entire `ataraxia` CLI, the CLI simply spawns `sudo` as a child process when invoking Nix commands that require root. This naturally triggers the user's PAM configuration (asking for password inline) and allows the Rust manager process to continue running seamlessly before and after elevation.

For a system-level switch:

```rust
// The child process (sudo) requests elevation; the parent (ataraxia) waits.
run_command("sudo", &["nixos-rebuild", "switch", "--flake", ...], workspace, dry_run)?;
```

For switching another user's Home Manager config:

```rust
// sudo -u alice home-manager switch --flake ...
run_command("sudo", &["-u", &user, "home-manager", "switch", "--flake", &hm_arg], workspace, dry_run)?;
```

---

## 3. Home Manager Integration

### Decision

Home Manager is integrated **exclusively through the NixOS module system** (`home-manager.nixosModules.home-manager`). The standalone `homeConfigurations` output in `core/flake.nix` should be **removed**.

### Rationale

- The CLI mediates **all** switches. Users should never call `home-manager switch --flake` directly.
- The inline `home-manager.users` binding in `users/default.nix` was the original integration path but is **also removed** — its role is fully handled by `core/flake.nix`'s NixOS module which sets `home-manager.useGlobalPkgs = true` and `home-manager.useUserPackages = true`.
- User HM configurations are imported via the host's NixOS evaluation, ensuring that the system build is the single source of truth.

### What Gets Removed

1. **`core/flake.nix` lines 61-94** — the standalone `homeConfigurations` output.
2. **`application/users/default.nix`** — this file's role (system user creation + HM binding) should be absorbed into the core module or host-level config.

### What the CLI Does

The CLI calls `nixos-rebuild switch` which triggers both system and HM changes in a single atomic operation. For user-only switches, the CLI will invoke `home-manager switch` internally (not exposed to the user).

---

## 4. Manifest Schema & CLI Surface

### Decision

The CLI's `users add` command only takes a `name`. All other user fields (`home`, `desktop`, `environment`, `groups`, `programs`) are set by manually editing `manifest.toml`.

### Removed CLI Flags

- `--desktop` — removed from `users add` (the `desktop` field remains in `manifest.toml` as the user's desktop startup command)
- `--environment` — removed from `users add`
- `--home` — removed from `users add`

### Scrapped Manifest Fields

The following fields exist in the current `manifest.toml` but are **not validated** by the manager and are **deferred to user Nix configuration** (or removed entirely):

- `timezone` — set in host's `default.nix`
- `nameservers` — set in host's `default.nix`
- `locale` — set in host's `default.nix`
- `environment` — semantics undefined; removed
- `programs` — semantics undefined; removed

The manifest's role is strictly **topology**: which hosts exist, which users exist, and which users are assigned to which hosts. Everything else belongs in Nix.

### Canonical Manifest Schema

```toml
[[hosts]]
name = "nihilicht-sagittarius"   # Required. Unique identifier.
arch = "x86_64-linux"            # Required. Nix system string.
users = ["tsukuyomi"]            # Required. Assigned user names.

[[users]]
name = "tsukuyomi"               # Required. Unique identifier.
home = true                      # Optional. Whether HM manages this user.
groups = ["wheel"]               # Optional. System groups.
```

---

## 5. Import Isolation (Boundary Enforcement)

### Decision

Strict import isolation (e.g. via static AST analysis) has been **dropped**. Since system-level folders like `hosts/` are owned by `root:root` with `755` permissions, any user can read them, meaning they can safely import them into their personal configurations. We accept this read-only access as non-threatening.

### What It Prevents (or Rather, Permits)

A user module at `users/alice/` *is* technically allowed to import files from `hosts/` or `core/` because the underlying filesystem grants read permissions. They cannot *modify* the system configuration.

### Rationale

Implementing a complex static analyzer for Nix ASTs in Rust adds severe development overhead and complexity for minimal security gain. As long as users cannot overwrite system config, importing existing system modules into user configurations is deemed an acceptable capability.

### Alternatives Rejected

- **Rust AST Parsing (rnix)**: Too complex for the marginal benefit.
- **Pre-commit hooks**: Relies on user setup. Users can bypass.
- **Nix `--restrict-eval`**: Too invasive; breaks legitimate nixpkgs imports.

---

## 6. Elevation Strategy (Dry-Run Scoping)

### Decision

Before executing a switch, the CLI performs a dry-run Nix evaluation to classify the scope of changes, then conditionally elevates.

```
UserOnly   → Switch user-level Home Manager configurations (User { users: Vec<String> })
System     → System-wide switch of the host (System)
```

> **Note**: For a system-wide switch, the `users` list is excluded from the `System` enum variant. This is because the NixOS evaluation rebuilds the host config, which automatically creates all system users and applies their Home Manager configurations inline (using the NixOS HM module). The manager doesn't need to manually orchestrate user switch loops when rebuilding system-wide.

### How to Detect System Changes

Compare the derivation output path against the currently active system profile:

```rust
fn has_system_changes(workspace: &Path, host: &str) -> Result<bool> {
    // 1. Evaluate the new system closure (without building)
    let output = duct::cmd("nix", &[
        "eval", "--raw",
        &format!(".#nixosConfigurations.{}.config.system.build.toplevel.drvPath", host),
    ])
    .dir(workspace)
    .read()?;

    // 2. Read the current active system derivation
    let current = std::fs::read_link("/run/current-system")
        .ok()
        .and_then(|p| {
            // The store path encodes the derivation
            p.to_str().map(|s| s.to_string())
        });

    // 3. If they differ, system changes exist
    Ok(current.as_deref() != Some(&output))
}
```

The comparison is between Nix store paths — if the new derivation path differs from `/run/current-system`, the system configuration has changed.

### Transient Git Trust

All Nix subprocess calls inject environment variables to allow read access to a root-owned workspace:

```rust
duct::cmd(program, args)
    .dir(workspace)
    .env("GIT_CONFIG_COUNT", "1")
    .env("GIT_CONFIG_KEY_0", "safe.directory")
    .env("GIT_CONFIG_VALUE_0", workspace.to_string_lossy().as_ref())
    .run()?;
```

This is injected per-subprocess, not persisted to any gitconfig.

*Note on Git Integration*: While Ataraxia manages some Git integration (like the uncommitted changes check), it relies entirely on the host system's native `git` executable rather than embedding complex libraries like `git2`. This maintains a lightweight footprint. Deferring all Git management (including this `safe.directory` trust) entirely to the user is an alternative approach, but for now, the framework injects this automatically to ensure a smooth out-of-the-box experience when the workspace is `root`-owned.

---

## 7. File Permission Enforcement

### Decision

File permissions are enforced via a **NixOS activation script** in `core/flake.nix`, using the `ataraxia.root` option (not a hardcoded `/etc/ataraxia` path).

### Implementation

```nix
system.activationScripts.ataraxia-permissions = {
  text = ''
    chown root:root ${config.ataraxia.root}
    chmod 755 ${config.ataraxia.root}
    ${lib.concatMapStrings (user: ''
      mkdir -p ${config.ataraxia.root}/users/${user.name}
      chown ${user.name}:${user.name} ${config.ataraxia.root}/users/${user.name}
      chmod 700 ${config.ataraxia.root}/users/${user.name}
    '') enabledUsers}
  '';
};
```

### Properties

- **Self-healing**: Permissions are re-enforced on every `nixos-rebuild switch`.
- **Uses `ataraxia.root`**: The workspace path is not hardcoded.
- **Root owns the repo**: `755` on root allows all users to read, only root to write.
- **Users own their dirs**: `700` on `users/<name>/` gives full access to the user and nobody else.

---

## 8. State Version Handling

### Decision

`home.stateVersion` is **not** set by the framework or the manifest. Users set it themselves in their own `home.nix`.

### Rationale

- `stateVersion` is a NixOS/HM operational concern, not an Ataraxia domain concept.
- It rarely changes and is per-deployment.
- Keeping it in the user's Nix config avoids polluting the manifest schema.

### Action

Remove the hardcoded `home.stateVersion = "23.11"` from `application/users/default.nix` (which is itself being removed — see §3).

---

## 9. Workspace Discovery

### Decision

**No upward directory traversal.** The workspace is determined by (in priority order):

1. `--workspace` / `-w` CLI flag
2. `ATARAXIA_WORKSPACE` environment variable
3. Current working directory

### Rationale

The workspace will ultimately live at a fixed, known location (`/etc/ataraxia` or equivalent). Cargo-style discovery adds complexity for a deployment tool that operates on a single, well-known workspace.

---

## 10. Manifest Persistence & Atomicity

### Decision

The `Manifest` struct uses `fd-lock` to guarantee atomic, thread-and-process-safe reads and writes to `manifest.toml`. The `Manifest` struct tracks a `dirty: bool` flag, and `save()` is only called when mutations occurred.

### Implementation (Completed)

- `Manifest` wraps the underlying file descriptors in an `fd_lock::RwLock`.
- `Manifest::from_workspace()` acquires a read lock to parse the AST.
- `Manifest::save()` acquires an exclusive write lock, preventing concurrent CLI instances from clobbering each other's configuration states.
- All mutation methods set `self.dirty = true` on success.
- `Cli::exec()` checks `manifest.is_dirty()` before saving.

### Benefits

- Prevents silent data loss or corrupted TOML ASTs during parallel invocations (e.g., from external automation scripts).
- Read-only commands no longer attempt to write the manifest, avoiding ownership conflicts.

---

## 11. Git Strictness & Velocity

### Decision

Git "dirty tracking" (uncommitted changes checking) and automatic lockfile commits have been **removed entirely**.

### Rationale

- Previously, the CLI used `git status --porcelain` to block system deployments if there were *any* uncommitted changes in the workspace (even modifying `README.md`).
- This created significant friction and severely hampered developer velocity.
- The `ataraxia sync` command now strictly performs `nix flake update` without any forced `git commit` semantics, deferring all version control lifecycle management back to the user.

---

## 12. Project Structure & Lifecycle

### Current Layout

```
ataraxia/
├── application/    # Test/development deployment instance
├── core/           # Library flake + Rust CLI
└── docs/           # Design documentation
```

### Future Layout

`application/` will be removed. `core/` will be promoted to the project root before publishing to GitHub. The test deployment will live in a separate repository or be managed as a flake input.

### Items to Remove Before Publishing

- `application/` directory (test deployment)
- `nixos.qcow2` (VM disk image, already gitignored)
- `application/manage_vm` (Fish script, superseded by CLI)

---

## 13. Scope Boundaries (What Ataraxia Is Not)

Decisions on what is explicitly **out of scope**:

| Topic | Decision | Rationale |
|---|---|---|
| Multi-host fleet deployment | ❌ Out of scope | Single device tool. Hosts are identity slots, not remote targets. |
| `aarch64-linux` support | Deferred | Cannot test currently. Manifest stores arch as free-form string, so the only constraint is the CLI `Architecture` enum. |
| Nix `or` syntax patterns | Not Ataraxia's concern | Host/user nix files are user-authored, not framework-owned. |
| `hardware-configuration.nix` | Not required | The `application/hosts/` directory is for testing only. Real deployments bring their own hardware config. |
| Pre-commit hooks | ❌ Rejected | Cannot trust user to set them up. All enforcement runs in the manager. |
| Manifest field validation beyond topology | Deferred | Fields like timezone, desktop are deferred to Nix config. Manifest validates only: unique names, referential integrity, type correctness of `home` and `groups`. |
