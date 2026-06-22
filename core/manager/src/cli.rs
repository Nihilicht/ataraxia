use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::str::FromStr;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Target {
    pub host: String,
    pub user: Option<String>,
}

impl FromStr for Target {
    type Err = std::convert::Infallible;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let (host, user) = if let Some((user, host)) = s.rsplit_once('@') {
            (host.to_string(), Some(user.to_string()))
        } else {
            (s.to_string(), None)
        };
        Ok(Target { host, user })
    }
}

/// Ataraxia: A Git-bound NixOS and Home-Manager orchestrator.
#[derive(Parser)]
#[command(version, about, long_about = None)]
pub struct Cli {
    #[command(subcommand)]
    pub cmd: Commands,

    /// Path to the workspace/configspace root (where manifest.toml and flake.lock live)
    #[arg(long, short, global = true, hide = true, env = "ATARAXIA_WORKSPACE")]
    pub workspace: Option<PathBuf>,

    /// Do not perform any changes; show what would be done
    #[arg(long, global = true)]
    pub dry_run: bool,

    /// Increase logging verbosity
    #[arg(short, long, global = true, action = clap::ArgAction::Count)]
    pub verbose: u8,
}

#[derive(Subcommand, Clone, Debug, PartialEq, Eq)]
pub enum Commands {
    /// Switch configuration to one or more targets (defaults to current host) and apply changes
    Switch {
        /// The targets to switch to (can be [user]@[host] or just [host])
        targets: Vec<Target>,
    },

    /// Build and run a VM of the configuration for one or more targets (defaults to current host)
    RunVm {
        /// The targets to run the VM for (can be [user]@[host] or just [host])
        targets: Vec<Target>,
    },

    /// Sync flake.lock to latest input versions
    Sync,

    /// Verify flake integrity and manifest consistency
    Check,

    /// Manage host definitions in manifest.toml
    Hosts {
        #[command(subcommand)]
        cmd: Option<HostCommands>,
    },

    /// Manage user definitions in manifest.toml
    Users {
        #[command(subcommand)]
        cmd: Option<UserCommands>,
    },
}

#[derive(Subcommand, Clone, Debug, PartialEq, Eq)]
pub enum HostCommands {
    /// Add a new host entry
    Add {
        name: String,
        /// System architecture
        #[arg(long, default_value = "x86_64-linux")]
        arch: Architecture,
    },
    /// Remove a host entry
    Sub { name: String },
    /// List all hosts in manifest
    List,
    /// Manage user assignments for a specific host
    Users {
        /// The host to manage users for
        host: String,

        /// Add users to the host
        #[arg(long, value_name = "USER")]
        add: Vec<String>,

        /// Remove users from the host
        #[arg(long, value_name = "USER")]
        sub: Vec<String>,

        /// User actions (+user to add, -user to remove)
        #[arg(allow_hyphen_values = true)]
        args: Vec<String>,
    },
}

#[derive(clap::ValueEnum, Clone, Debug, PartialEq, Eq)]
pub enum Architecture {
    #[value(name = "x86_64-linux")]
    X86_64Linux,
}

#[derive(Subcommand, Clone, Debug, PartialEq, Eq)]
pub enum UserCommands {
    /// Create a global user definition
    Add {
        name: String,
    },
    /// Remove a global user definition
    Sub { name: String },
    /// List all users in manifest
    List,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_target() {
        assert_eq!(
            Target::from_str("host1").unwrap(),
            Target {
                host: "host1".to_string(),
                user: None
            }
        );
        assert_eq!(
            Target::from_str("user1@host1").unwrap(),
            Target {
                host: "host1".to_string(),
                user: Some("user1".to_string())
            }
        );
        assert_eq!(
            Target::from_str("user.name@some-host").unwrap(),
            Target {
                host: "some-host".to_string(),
                user: Some("user.name".to_string())
            }
        );
        assert_eq!(
            Target::from_str("@host1").unwrap(),
            Target {
                host: "host1".to_string(),
                user: Some("".to_string())
            }
        );
        assert_eq!(
            Target::from_str("user1@").unwrap(),
            Target {
                host: "".to_string(),
                user: Some("user1".to_string())
            }
        );
        assert_eq!(
            Target::from_str("@").unwrap(),
            Target {
                host: "".to_string(),
                user: Some("".to_string())
            }
        );
        assert_eq!(
            Target::from_str("").unwrap(),
            Target {
                host: "".to_string(),
                user: None
            }
        );
    }

    #[test]
    fn test_cli_parsing() {
        let args = vec!["ataraxia", "switch", "user1@host1", "user2@", "@host3", "@"];
        let cli = Cli::try_parse_from(args).unwrap();
        assert_eq!(cli.workspace, None);
        match cli.cmd {
            Commands::Switch { targets } => {
                assert_eq!(
                    targets,
                    vec![
                        Target {
                            host: "host1".to_string(),
                            user: Some("user1".to_string())
                        },
                        Target {
                            host: "".to_string(),
                            user: Some("user2".to_string())
                        },
                        Target {
                            host: "host3".to_string(),
                            user: Some("".to_string())
                        },
                        Target {
                            host: "".to_string(),
                            user: Some("".to_string())
                        }
                    ]
                );
            }
            _ => panic!("Expected Switch command"),
        }

        let args_none = vec!["ataraxia", "switch"];
        let cli_none = Cli::try_parse_from(args_none).unwrap();
        match cli_none.cmd {
            Commands::Switch { targets } => {
                assert!(targets.is_empty());
            }
            _ => panic!("Expected Switch command"),
        }

        let args_workspace = vec!["ataraxia", "--workspace", "/tmp/ataraxia", "switch"];
        let cli_workspace = Cli::try_parse_from(args_workspace).unwrap();
        assert_eq!(
            cli_workspace.workspace,
            Some(PathBuf::from("/tmp/ataraxia"))
        );

        let args_hosts_default = vec!["ataraxia", "hosts"];
        let cli_hosts_default = Cli::try_parse_from(args_hosts_default).unwrap();
        assert_eq!(
            cli_hosts_default.cmd,
            Commands::Hosts { cmd: None }
        );

        let args_hosts_list = vec!["ataraxia", "hosts", "list"];
        let cli_hosts_list = Cli::try_parse_from(args_hosts_list).unwrap();
        assert_eq!(
            cli_hosts_list.cmd,
            Commands::Hosts {
                cmd: Some(HostCommands::List)
            }
        );

        let args_users_default = vec!["ataraxia", "users"];
        let cli_users_default = Cli::try_parse_from(args_users_default).unwrap();
        assert_eq!(
            cli_users_default.cmd,
            Commands::Users { cmd: None }
        );

        let args_users_list = vec!["ataraxia", "users", "list"];
        let cli_users_list = Cli::try_parse_from(args_users_list).unwrap();
        assert_eq!(
            cli_users_list.cmd,
            Commands::Users {
                cmd: Some(UserCommands::List)
            }
        );

        let args_run_vm = vec!["ataraxia", "run-vm", "user1@host1"];
        let cli_run_vm = Cli::try_parse_from(args_run_vm).unwrap();
        match cli_run_vm.cmd {
            Commands::RunVm { targets } => {
                assert_eq!(
                    targets,
                    vec![Target {
                        host: "host1".to_string(),
                        user: Some("user1".to_string())
                    }]
                );
            }
            _ => panic!("Expected RunVm command"),
        }
    }
}
