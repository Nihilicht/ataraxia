use crate::cli;
use crate::manifest::{Manifest, resolve_host, resolve_user};
use owo_colors::OwoColorize;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResolvedTarget {
    /// Switch user-level Home Manager configurations only (no root, no nixos-rebuild)
    User { host: String, users: Vec<String> },
    /// System-wide switch of the host (nixos-rebuild only, HM is evaluated inline by NixOS)
    System { host: String },
}

impl ResolvedTarget {
    pub fn host(&self) -> &str {
        match self {
            Self::User { host, .. } => host,
            Self::System { host } => host,
        }
    }
}



fn has_system_changes(workspace: &std::path::Path, host: &str, ctx: &impl crate::context::Context) -> anyhow::Result<bool> {
    let output = ctx.run_command_with_output("nix", &[
        "eval", "--raw",
        &format!(".#nixosConfigurations.{}.config.system.build.toplevel.drvPath", host),
    ], workspace).map_err(|e| anyhow::anyhow!("failed to evaluate system configuration: {}", e))?;

    let current = ctx.read_link(std::path::Path::new("/run/current-system"))
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()));

    Ok(current.as_deref() != Some(output.trim()))
}

/// Absorbs/resolves raw CLI targets against the manifest and environment into a single `ResolvedTarget`.
///
/// Rules:
/// - Empty target list: defaults to targeting the current host with all its assigned users.
/// - Empty host name: resolves to current system hostname.
/// - Specific user requested (e.g. user@host): targets only that user on the host.
/// - No user requested (e.g. host): targets all users assigned to that host in the manifest.
/// - Merges multiple user requests for the same host into a single `ResolvedTarget` entry.
/// - Returns an error if the targets resolve to more than one unique host, as building/deploying
///   to multiple hosts concurrently is not supported.
pub fn absorb_target(
    targets: &[cli::Target],
    manifest: &Manifest,
    current_hostname: &str,
    current_user: &str,
) -> anyhow::Result<ResolvedTarget> {
    let mut resolved_hosts: Vec<ResolvedTarget> = Vec::new();

    let targets_to_resolve = if targets.is_empty() {
        std::borrow::Cow::Owned(vec![cli::Target {
            host: String::new(),
            user: None,
        }])
    } else {
        std::borrow::Cow::Borrowed(targets)
    };

    for target in targets_to_resolve.iter() {
        // 1. Resolve host name
        let host = if target.host.is_empty() {
            current_hostname.to_string()
        } else {
            target.host.clone()
        };

        // 1.5. Validate host against manifest
        manifest.check_host(&host).ok_or_else(|| {
            anyhow::anyhow!("host '{}' is not defined in the manifest", host)
        })?;

        // 2. Resolve target scope (User vs System)
        let resolved = match &target.user {
            Some(user) => {
                if user.is_empty() {
                    // System switch: @host or @
                    ResolvedTarget::System { host: host.clone() }
                } else {
                    // Specific user
                    let assigned_users = manifest.list_users_for_host(&host).unwrap_or_default();
                    if !assigned_users.contains(&user.as_str()) {
                        anyhow::bail!("user '{}' is not assigned to host '{}'", user, host);
                    }
                    ResolvedTarget::User {
                        host: host.clone(),
                        users: vec![user.clone()],
                    }
                }
            }
            None => {
                // No user specified: default to current user (User switch only)
                let user_resolved = current_user.to_string();
                let assigned_users = manifest.list_users_for_host(&host).unwrap_or_default();
                if !assigned_users.contains(&user_resolved.as_str()) {
                    anyhow::bail!("user '{}' is not assigned to host '{}'", user_resolved, host);
                }
                ResolvedTarget::User {
                    host: host.clone(),
                    users: vec![user_resolved],
                }
            }
        };

        // 3. Insert or merge into resolved hosts list
        if let Some(existing) = resolved_hosts.iter_mut().find(|rt| rt.host() == host) {
            match (&mut *existing, resolved) {
                (ResolvedTarget::User { users: existing_users, .. }, ResolvedTarget::User { users: new_users, .. }) => {
                    for u in new_users {
                        if !existing_users.contains(&u) {
                            existing_users.push(u);
                        }
                    }
                }
                (e, _) => {
                    // If either is System, the merged scope is System (System covers all user configs)
                    *e = ResolvedTarget::System { host };
                }
            }
        } else {
            resolved_hosts.push(resolved);
        }
    }

    if resolved_hosts.is_empty() {
        let host = current_hostname.to_string();
        Ok(ResolvedTarget::User { host, users: Vec::new() })
    } else if resolved_hosts.len() > 1 {
        let hosts: Vec<String> = resolved_hosts.iter().map(|rt| rt.host().to_string()).collect();
        anyhow::bail!(
            "targeting multiple hosts simultaneously is logically invalid (resolved to: {})",
            hosts.join(", ")
        )
    } else {
        Ok(resolved_hosts.remove(0))
    }
}

impl cli::Cli {
    pub fn exec(self) -> anyhow::Result<()> {
        let workspace = self.workspace.clone().unwrap_or_else(|| {
            std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."))
        });
        tracing::debug!("Workspace path: {:?}", workspace);
        tracing::debug!("Dry run enabled: {}", self.dry_run);

        // Load the manifest from the workspace
        let mut manifest = Manifest::from_workspace(&workspace)?;
        let ctx = crate::context::RealContext;

        self.cmd.exec(self.dry_run, &mut manifest, &workspace, &ctx)?;

        if manifest.is_dirty() && !self.dry_run {
            manifest.save(&workspace)?;
        }

        Ok(())
    }
}

impl cli::Commands {
    fn exec(
        &self,
        dry_run: bool,
        manifest: &mut Manifest,
        workspace: &std::path::Path,
        ctx: &impl crate::context::Context,
    ) -> anyhow::Result<()> {
        match self {
            Self::Switch { targets } => {
                let current_host = ctx.get_current_hostname().unwrap_or_default();
                let current_user = ctx.get_current_user().unwrap_or_default();
                let resolved = absorb_target(targets, manifest, &current_host, &current_user)?;
                tracing::info!("Switching target resolved to: {:?}", resolved);

                match &resolved {
                    ResolvedTarget::System { host } => {
                        if !has_system_changes(workspace, host, ctx)? {
                            tracing::info!("No system changes detected for host '{}'. Skipping rebuild.", host);
                        } else {
                            let flake_arg = format!("{}#{}", workspace.to_string_lossy(), host);
                            if ctx.is_root() {
                                ctx.run_command(
                                    "nixos-rebuild",
                                    &["switch", "--flake", &flake_arg],
                                    workspace,
                                    dry_run,
                                )?;
                            } else {
                                tracing::info!("System-level changes detected. Elevating...");
                                ctx.run_command(
                                    "sudo",
                                    &["nixos-rebuild", "switch", "--flake", &flake_arg],
                                    workspace,
                                    dry_run,
                                )?;
                            }
                        }
                    }
                    ResolvedTarget::User { host, users } => {
                        for user in users {
                            let hm_flake_arg = format!(
                                "{}#{}@{}",
                                workspace.to_string_lossy(),
                                user,
                                host
                            );
                            let current_user_env = ctx.get_current_user().unwrap_or_default();
                            if user == &current_user_env || ctx.is_root() {
                                ctx.run_command(
                                    "home-manager",
                                    &["switch", "--flake", &hm_flake_arg],
                                    workspace,
                                    dry_run,
                                )?;
                            } else {
                                tracing::info!("Switching configuration for user '{}'. Elevating...", user);
                                ctx.run_command(
                                    "sudo",
                                    &["-u", user, "home-manager", "switch", "--flake", &hm_flake_arg],
                                    workspace,
                                    dry_run,
                                )?;
                            }
                        }
                    }
                }
                Ok(())
            }
            Self::RunVm { targets } => {
                let current_host = ctx.get_current_hostname().unwrap_or_default();
                let current_user = ctx.get_current_user().unwrap_or_default();
                let resolved = absorb_target(targets, manifest, &current_host, &current_user)?;
                tracing::info!("Running VM of configuration resolved to: {:?}", resolved);

                // Build and run the VM
                let target_arg = format!(
                    ".#nixosConfigurations.{}.config.system.build.vm",
                    resolved.host()
                );
                ctx.run_command("nix", &["build", &target_arg], workspace, dry_run)?;
                let vm_bin = format!("./result/bin/run-{}-vm", resolved.host());
                ctx.run_command(&vm_bin, &[], workspace, dry_run)?;
                Ok(())
            }
            Self::Sync => {
                tracing::info!("Syncing flake inputs...");
                ctx.run_command("nix", &["flake", "update"], workspace, dry_run)?;
                Ok(())
            }
            Self::Check => {
                tracing::info!("Checking manifest soundness and flake integrity...");
                manifest.verify()?;
                ctx.run_command("nix", &["flake", "check"], workspace, dry_run)?;
                Ok(())
            }
            Self::Hosts { cmd } => {
                if let Some(cmd) = cmd {
                    cmd.exec(dry_run, manifest, workspace)
                } else {
                    cli::HostCommands::List.exec(dry_run, manifest, workspace)
                }
            }
            Self::Users { cmd } => {
                if let Some(cmd) = cmd {
                    cmd.exec(dry_run, manifest, workspace)
                } else {
                    cli::UserCommands::List.exec(dry_run, manifest, workspace)
                }
            }
        }
    }
}

impl cli::HostCommands {
    fn exec(&self, _dry_run: bool, manifest: &mut Manifest, _workspace: &std::path::Path) -> anyhow::Result<()> {
        match self {
            Self::Add { name, arch } => {
                let arch_str = match arch {
                    cli::Architecture::X86_64Linux => "x86_64-linux",
                };
                let display = resolve_host(name)?;
                manifest.add_host(name, arch_str)?;
                println!("{} host '{}'", "added".green().bold(), display.as_ref().cyan().bold());
                Ok(())
            }
            Self::Sub { name } => {
                let display = resolve_host(name)?;
                manifest.sub_host(name)?;
                println!("{} host '{}'", "removed".red().bold(), display.as_ref().cyan().bold());
                Ok(())
            }
            Self::List => {
                let hosts = manifest.list_hosts();
                if hosts.is_empty() {
                    println!("{}", "no hosts defined".dimmed());
                } else {
                    for host in hosts {
                        println!("{}", host);
                    }
                }
                Ok(())
            }
            Self::Users {
                host,
                add,
                sub,
                args,
            } => {
                let mut to_add: Vec<&str> = add.iter().map(|s| s.as_str()).collect();
                let mut to_sub: Vec<&str> = sub.iter().map(|s| s.as_str()).collect();
                for arg in args {
                    if let Some(user) = arg.strip_prefix('+') {
                        to_add.push(user);
                    } else if let Some(user) = arg.strip_prefix('-') {
                        to_sub.push(user);
                    } else {
                        anyhow::bail!("invalid user assignment argument '{}': expected +user or -user", arg);
                    }
                }

                for user in &to_add {
                    manifest.add_user_to_host(host, user)?;
                    println!(
                        "{} user '{}' to host '{}'",
                        "assigned".green().bold(),
                        user.green().bold(),
                        host.cyan().bold()
                    );
                }
                for user in &to_sub {
                    manifest.sub_user_from_host(host, user)?;
                    println!(
                        "{} user '{}' from host '{}'",
                        "unassigned".red().bold(),
                        user.green().bold(),
                        host.cyan().bold()
                    );
                }

                if to_add.is_empty() && to_sub.is_empty() {
                    if let Some(users) = manifest.list_users_for_host(host) {
                        if users.is_empty() {
                            println!("{}", "no users assigned".dimmed());
                        } else {
                            for user in users {
                                println!("{}", user);
                            }
                        }
                    } else {
                        let display = resolve_host(host)?;
                        anyhow::bail!("host '{}' not found", display.as_ref().cyan().bold());
                    }
                }
                Ok(())
            }
        }
    }
}

impl cli::UserCommands {
    fn exec(&self, _dry_run: bool, manifest: &mut Manifest, _workspace: &std::path::Path) -> anyhow::Result<()> {
        match self {
            Self::Add { name } => {
                let display = resolve_user(name)?;
                manifest.add_user(name)?;
                println!("{} user '{}'", "added".green().bold(), display.as_ref().green().bold());
                Ok(())
            }
            Self::Sub { name } => {
                let display = resolve_user(name)?;
                manifest.sub_user(name)?;
                println!("{} user '{}'", "removed".red().bold(), display.as_ref().green().bold());
                Ok(())
            }
            Self::List => {
                let users = manifest.list_users();
                if users.is_empty() {
                    println!("{}", "no users defined".dimmed());
                } else {
                    for user in users {
                        println!("{}", user);
                    }
                }
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    #[test]
    fn test_absorb_target_basic() {
        let toml_content = r#"
            [[hosts]]
            name = "host-a"
            users = ["user-1", "user-2", "testuser"]

            [[hosts]]
            name = "host-b"
            users = ["testuser"]

            [[users]]
            name = "user-1"

            [[users]]
            name = "user-2"
            
            [[users]]
            name = "testuser"
        "#;
        let manifest = Manifest::from_str(toml_content).unwrap();

        // 1. Specific host without user -> should get current user only, no system
        let targets = vec![cli::Target {
            host: "host-a".to_string(),
            user: None,
        }];
        let resolved = absorb_target(&targets, &manifest, "host-a", "testuser").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::User {
                host: "host-a".to_string(),
                users: vec!["testuser".to_string()]
            }
        );

        // 2. Specific host with specific user
        let targets = vec![cli::Target {
            host: "host-a".to_string(),
            user: Some("user-2".to_string()),
        }];
        let resolved = absorb_target(&targets, &manifest, "host-a", "testuser").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::User {
                host: "host-a".to_string(),
                users: vec!["user-2".to_string()]
            }
        );

        // 3. Merging multiple targets on the same host
        let targets = vec![
            cli::Target {
                host: "host-a".to_string(),
                user: Some("user-1".to_string()),
            },
            cli::Target {
                host: "host-a".to_string(),
                user: Some("".to_string()), // @host-a (triggers system-wide switch)
            },
        ];
        let resolved = absorb_target(&targets, &manifest, "host-a", "testuser").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::System {
                host: "host-a".to_string(),
            }
        );

        // 4. Host with no assigned users but asking for system switch
        let targets = vec![cli::Target {
            host: "host-b".to_string(),
            user: Some("".to_string()),
        }];
        let resolved = absorb_target(&targets, &manifest, "host-a", "testuser").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::System {
                host: "host-b".to_string(),
            }
        );

        // 5. Targeting multiple distinct hosts -> should error
        let targets = vec![
            cli::Target {
                host: "host-a".to_string(),
                user: None,
            },
            cli::Target {
                host: "host-b".to_string(),
                user: None,
            },
        ];
        let err = absorb_target(&targets, &manifest, "host-a", "testuser").unwrap_err();
        assert!(
            err.to_string()
                .contains("targeting multiple hosts simultaneously is logically invalid")
        );
    }

    #[test]
    fn test_absorb_target_aggressive() {
        let toml_content = r#"
            [[hosts]]
            name = "workstation"
            users = ["admin", "guest"]

            [[hosts]]
            name = "server"
            users = ["admin"]

            [[users]]
            name = "admin"
            
            [[users]]
            name = "guest"
        "#;
        let manifest = Manifest::from_str(toml_content).unwrap();

        // 1. Target empty string (implicitly current host + current user)
        let targets = vec![cli::Target {
            host: "".to_string(),
            user: None,
        }];
        let resolved = absorb_target(&targets, &manifest, "workstation", "guest").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::User {
                host: "workstation".to_string(),
                users: vec!["guest".to_string()]
            }
        );

        // 2. Empty string but current user not on host -> should error
        let err = absorb_target(&targets, &manifest, "server", "guest").unwrap_err();
        assert!(err.to_string().contains("is not assigned to host 'server'"));

        // 3. User requesting '@' on current host
        let targets = vec![cli::Target {
            host: "".to_string(),
            user: Some("".to_string()),
        }];
        let resolved = absorb_target(&targets, &manifest, "workstation", "guest").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::System {
                host: "workstation".to_string(),
            }
        );

        // 4. Unknown host -> should error
        let targets = vec![cli::Target {
            host: "unknown-host".to_string(),
            user: None,
        }];
        let err = absorb_target(&targets, &manifest, "workstation", "guest").unwrap_err();
        assert!(err.to_string().contains("not defined in the manifest"));

        // 5. Multiple users on same host
        let targets = vec![
            cli::Target {
                host: "workstation".to_string(),
                user: Some("guest".to_string()),
            },
            cli::Target {
                host: "workstation".to_string(),
                user: Some("admin".to_string()),
            },
        ];
        let resolved = absorb_target(&targets, &manifest, "server", "admin").unwrap();
        assert_eq!(
            resolved,
            ResolvedTarget::User {
                host: "workstation".to_string(),
                users: vec!["guest".to_string(), "admin".to_string()]
            }
        );
    }

    #[test]
    fn test_execution_mock_context() {
        use crate::context::MockContext;
        
        let toml_content = r#"
            [[hosts]]
            name = "workstation"
            users = ["admin", "guest"]

            [[users]]
            name = "admin"
            
            [[users]]
            name = "guest"
        "#;
        let mut manifest = Manifest::from_str(toml_content).unwrap();

        let mut ctx = MockContext::new("workstation", "guest", false);
        ctx.set_active_system("/nix/store/111-nixos-system-workstation");
        ctx.mock_output(
            "nix eval --raw .#nixosConfigurations.workstation.config.system.build.toplevel.drvPath",
            "/nix/store/222-nixos-system-workstation-new"
        );

        let cmd = cli::Commands::Switch {
            targets: vec![cli::Target {
                host: "".to_string(),
                user: Some("".to_string()), // @ triggers system switch
            }],
        };

        cmd.exec(false, &mut manifest, std::path::Path::new("/tmp/workspace"), &ctx).unwrap();

        let commands = ctx.commands_run.lock().unwrap();
        // Should use sudo because ctx.is_root() == false
        assert!(commands.contains(&"sudo nixos-rebuild switch --flake /tmp/workspace#workstation".to_string()));
    }

    #[test]
    fn test_execution_mock_context_user_switch() {
        use crate::context::MockContext;
        
        let toml_content = r#"
            [[hosts]]
            name = "workstation"
            users = ["admin", "guest"]

            [[users]]
            name = "admin"
            
            [[users]]
            name = "guest"
        "#;
        let mut manifest = Manifest::from_str(toml_content).unwrap();

        let ctx = MockContext::new("workstation", "guest", false);

        let cmd = cli::Commands::Switch {
            targets: vec![cli::Target {
                host: "".to_string(),
                user: Some("admin".to_string()), // switch to a different user
            }],
        };

        cmd.exec(false, &mut manifest, std::path::Path::new("/tmp/workspace"), &ctx).unwrap();

        let commands = ctx.commands_run.lock().unwrap();
        // Should use sudo because current_user (guest) != target_user (admin) and not root
        assert!(commands.contains(&"sudo -u admin home-manager switch --flake /tmp/workspace#admin@workstation".to_string()));
    }

}

