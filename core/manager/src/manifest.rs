use std::borrow::Cow;
use std::str::FromStr;
use toml_edit::DocumentMut;
use owo_colors::OwoColorize;

#[derive(Debug, Clone)]
pub struct Manifest {
    doc: DocumentMut,
    dirty: bool,
}

/// Helper to get the current system hostname.
pub fn get_current_hostname() -> Option<String> {
    nix::unistd::gethostname()
        .ok()
        .map(|h| h.to_string_lossy().into_owned())
}

/// Resolves a hostname, defaulting to the current system hostname if empty.
pub fn resolve_host(name: &str) -> anyhow::Result<Cow<'_, str>> {
    if name.is_empty() {
        get_current_hostname()
            .map(Cow::Owned)
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "system error".red().bold(),
                    "could not resolve current hostname"
                )
            })
    } else {
        Ok(Cow::Borrowed(name))
    }
}

/// Resolves a username, defaulting to the current `$USER` if empty.
pub fn resolve_user(name: &str) -> anyhow::Result<Cow<'_, str>> {
    if name.is_empty() {
        std::env::var("USER")
            .map(Cow::Owned)
            .map_err(|_| {
                anyhow::anyhow!(
                    "{}: {}",
                    "system error".red().bold(),
                    "could not resolve current user name"
                )
            })
    } else {
        Ok(Cow::Borrowed(name))
    }
}

impl Manifest {
    /// Lists all host names in the manifest.
    pub fn list_hosts(&self) -> Vec<&str> {
        self.doc
            .get("hosts")
            .and_then(|v| v.as_array_of_tables())
            .map(|array| {
                array
                    .iter()
                    .filter_map(|table| table.get("name").and_then(|v| v.as_str()))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Lists all user names in the manifest.
    pub fn list_users(&self) -> Vec<&str> {
        self.doc
            .get("users")
            .and_then(|v| v.as_array_of_tables())
            .map(|array| {
                array
                    .iter()
                    .filter_map(|table| table.get("name").and_then(|v| v.as_str()))
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Lists all user names assigned to a specific host in the manifest.
    ///
    /// If `host` is empty, it resolves to the current system hostname.
    /// If the resolved host is not found in the manifest, returns `None`.
    pub fn list_users_for_host<'a>(&'a self, host: &str) -> Option<Vec<&'a str>> {
        let resolved = resolve_host(host).ok()?;

        let hosts_array = self.doc.get("hosts")?.as_array_of_tables()?;
        let host_table = hosts_array.iter().find(|table| {
            table.get("name").and_then(|v| v.as_str()) == Some(resolved.as_ref())
        })?;

        let users = host_table
            .get("users")
            .and_then(|v| v.as_array())
            .map(|array| {
                array
                    .iter()
                    .filter_map(|v| v.as_str())
                    .collect()
            })
            .unwrap_or_default();

        Some(users)
    }

    /// Adds a new host to the manifest.
    ///
    /// Returns an error if the host already exists.
    pub fn add_host(&mut self, name: &str, arch: &str) -> anyhow::Result<()> {
        let resolved = resolve_host(name)?;

        if self.check_host(&resolved).is_some() {
            anyhow::bail!(
                "host '{}' already exists",
                resolved.as_ref().cyan().bold()
            );
        }

        if self.doc.get("hosts").is_none() {
            self.doc.insert("hosts", toml_edit::Item::ArrayOfTables(toml_edit::ArrayOfTables::new()));
        }
        let array = self.doc.get_mut("hosts")
            .unwrap()
            .as_array_of_tables_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'hosts' is not an array of tables"
                )
            })?;

        let mut new_host = toml_edit::Table::new();
        new_host.insert("name", toml_edit::value(resolved.as_ref()));
        new_host.insert("arch", toml_edit::value(arch));
        new_host.insert("users", toml_edit::Item::Value(toml_edit::Value::Array(toml_edit::Array::new())));

        array.push(new_host);
        self.dirty = true;
        Ok(())
    }

    /// Removes a host from the manifest.
    ///
    /// Returns an error if the host does not exist.
    pub fn sub_host(&mut self, name: &str) -> anyhow::Result<()> {
        let resolved = resolve_host(name)?;

        let hosts_entry = self.doc.get_mut("hosts")
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "no hosts defined"
                )
            })?;
        let array = hosts_entry
            .as_array_of_tables_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'hosts' is not an array of tables"
                )
            })?;

        let pos = array.iter().position(|table| {
            table.get("name").and_then(|v| v.as_str()) == Some(resolved.as_ref())
        });

        if let Some(idx) = pos {
            array.remove(idx);
            self.dirty = true;
            Ok(())
        } else {
            anyhow::bail!(
                "host '{}' not found",
                resolved.as_ref().cyan().bold()
            );
        }
    }

    /// Adds a new user to the manifest.
    ///
    /// Returns an error if the user already exists.
    pub fn add_user(&mut self, name: &str) -> anyhow::Result<()> {
        let resolved = resolve_user(name)?;

        if self.check_user(&resolved).is_some() {
            anyhow::bail!(
                "user '{}' already exists",
                resolved.as_ref().green().bold()
            );
        }

        if self.doc.get("users").is_none() {
            self.doc.insert("users", toml_edit::Item::ArrayOfTables(toml_edit::ArrayOfTables::new()));
        }
        let array = self.doc.get_mut("users")
            .unwrap()
            .as_array_of_tables_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'users' is not an array of tables"
                )
            })?;

        let mut new_user = toml_edit::Table::new();
        new_user.insert("name", toml_edit::value(resolved.as_ref()));

        array.push(new_user);
        self.dirty = true;
        Ok(())
    }

    /// Removes a user from the manifest.
    ///
    /// Returns an error if the user does not exist.
    pub fn sub_user(&mut self, name: &str) -> anyhow::Result<()> {
        let resolved = resolve_user(name)?;

        let users_entry = self.doc.get_mut("users")
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "no users defined"
                )
            })?;
        let array = users_entry
            .as_array_of_tables_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'users' is not an array of tables"
                )
            })?;

        let pos = array.iter().position(|table| {
            table.get("name").and_then(|v| v.as_str()) == Some(resolved.as_ref())
        });

        if let Some(idx) = pos {
            array.remove(idx);
            self.dirty = true;
            Ok(())
        } else {
            anyhow::bail!(
                "user '{}' not found",
                resolved.as_ref().green().bold()
            );
        }
    }

    /// Assigns a user to a specific host's user assignments.
    ///
    /// Returns an error if the host does not exist or user is already assigned to host.
    pub fn add_user_to_host(&mut self, host: &str, user: &str) -> anyhow::Result<()> {
        let resolved_host = resolve_host(host)?;

        let resolved_user = resolve_user(user)?;

        if self.check_user(&resolved_user).is_none() {
            anyhow::bail!(
                "user '{}' not found",
                resolved_user.as_ref().green().bold()
            );
        }

        let hosts_array = self.doc.get_mut("hosts")
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "no hosts defined"
                )
            })?
            .as_array_of_tables_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'hosts' is not an array of tables"
                )
            })?;

        let host_table = hosts_array.iter_mut().find(|table| {
            table.get("name").and_then(|v| v.as_str()) == Some(resolved_host.as_ref())
        }).ok_or_else(|| {
            anyhow::anyhow!(
                "host '{}' not found",
                resolved_host.as_ref().cyan().bold()
            )
        })?;

        if host_table.get("users").is_none() {
            host_table.insert("users", toml_edit::Item::Value(toml_edit::Value::Array(toml_edit::Array::new())));
        }

        let users_array = host_table.get_mut("users")
            .unwrap()
            .as_array_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'users' key is not an array"
                )
            })?;

        let exists = users_array.iter().any(|v| v.as_str() == Some(resolved_user.as_ref()));
        if exists {
            anyhow::bail!(
                "user '{}' is already assigned to host '{}'",
                resolved_user.as_ref().green().bold(),
                resolved_host.as_ref().cyan().bold()
            );
        }

        users_array.push(resolved_user.as_ref());
        self.dirty = true;
        Ok(())
    }

    /// Removes a user from a specific host's user assignments.
    ///
    /// Returns an error if the host or user does not exist or user is not assigned to host.
    pub fn sub_user_from_host(&mut self, host: &str, user: &str) -> anyhow::Result<()> {
        let resolved_host = resolve_host(host)?;

        let resolved_user = resolve_user(user)?;

        if self.check_user(&resolved_user).is_none() {
            anyhow::bail!(
                "user '{}' not found",
                resolved_user.as_ref().green().bold()
            );
        }

        let hosts_array = self.doc.get_mut("hosts")
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "no hosts defined"
                )
            })?
            .as_array_of_tables_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'hosts' is not an array of tables"
                )
            })?;

        let host_table = hosts_array.iter_mut().find(|table| {
            table.get("name").and_then(|v| v.as_str()) == Some(resolved_host.as_ref())
        }).ok_or_else(|| {
            anyhow::anyhow!(
                "host '{}' not found",
                resolved_host.as_ref().cyan().bold()
            )
        })?;

        let users_item = host_table.get_mut("users")
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: no users assigned to host '{}'",
                    "invalid document structure".yellow().bold(),
                    resolved_host.as_ref().cyan().bold()
                )
            })?;

        let users_array = users_item
            .as_array_mut()
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    "'users' key is not an array"
                )
            })?;

        let pos = users_array.iter().position(|v| v.as_str() == Some(resolved_user.as_ref()));
        if let Some(idx) = pos {
            users_array.remove(idx);
            self.dirty = true;
            Ok(())
        } else {
            anyhow::bail!(
                "user '{}' is not assigned to host '{}'",
                resolved_user.as_ref().green().bold(),
                resolved_host.as_ref().cyan().bold()
            );
        }
    }

    /// Checks if a hostname exists in the manifest.
    ///
    /// If `host` is empty, it resolves to the current system hostname.
    /// Returns `Some(Cow)` with the resolved name if valid, otherwise `None`.
    pub fn check_host<'a>(&self, host: &'a str) -> Option<Cow<'a, str>> {
        let resolved = resolve_host(host).ok()?;

        let hosts_array = self.doc.get("hosts")?.as_array_of_tables()?;
        let exists = hosts_array
            .iter()
            .any(|table| table.get("name").and_then(|v| v.as_str()) == Some(&resolved));

        if exists { Some(resolved) } else { None }
    }

    /// Checks if a username exists in the manifest.
    ///
    /// If `user` is empty, it resolves to the current system username.
    /// Returns `Some(Cow)` with the resolved name if valid, otherwise `None`.
    pub fn check_user<'a>(&self, user: &'a str) -> Option<Cow<'a, str>> {
        let resolved = resolve_user(user).ok()?;

        let users_array = self.doc.get("users")?.as_array_of_tables()?;
        let exists = users_array
            .iter()
            .any(|table| table.get("name").and_then(|v| v.as_str()) == Some(&resolved));

        if exists { Some(resolved) } else { None }
    }

    /// Verifies the semantic soundness of the manifest.
    ///
    /// Checks for:
    /// - Duplicate host names
    /// - Duplicate user names
    /// - Reference integrity (assigned users must exist globally)
    pub fn verify(&self) -> anyhow::Result<()> {
        use std::collections::HashSet;

        let mut host_names = HashSet::new();
        if let Some(hosts_array) = self.doc.get("hosts").and_then(|v| v.as_array_of_tables()) {
            for table in hosts_array.iter() {
                let name = table.get("name")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| {
                        anyhow::anyhow!(
                            "{}: {}",
                            "invalid document structure".yellow().bold(),
                            "missing host name"
                        )
                    })?;

                if !host_names.insert(name) {
                    anyhow::bail!(
                        "{}: duplicate host name '{}'",
                        "validation error".red().bold(),
                        name.cyan().bold()
                    );
                }
            }
        }

        let mut user_names = HashSet::new();
        if let Some(users_array) = self.doc.get("users").and_then(|v| v.as_array_of_tables()) {
            for table in users_array.iter() {
                let name = table.get("name")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| {
                        anyhow::anyhow!(
                            "{}: {}",
                            "invalid document structure".yellow().bold(),
                            "missing user name"
                        )
                    })?;

                if !user_names.insert(name) {
                    anyhow::bail!(
                        "{}: duplicate user name '{}'",
                        "validation error".red().bold(),
                        name.green().bold()
                    );
                }

                if let Some(home_val) = table.get("home")
                    && home_val.as_bool().is_none()
                {
                    anyhow::bail!(
                        "{}: 'home' field for user '{}' is not a boolean",
                        "invalid document structure".yellow().bold(),
                        name.green().bold()
                    );
                }

                if let Some(groups_val) = table.get("groups") {
                    if let Some(groups_array) = groups_val.as_array() {
                        for val in groups_array.iter() {
                            if val.as_str().is_none() {
                                anyhow::bail!(
                                    "{}: non-string value in user '{}' groups list",
                                    "invalid document structure".yellow().bold(),
                                    name.green().bold()
                                );
                            }
                        }
                    } else {
                        anyhow::bail!(
                            "{}: 'groups' field for user '{}' is not an array",
                            "invalid document structure".yellow().bold(),
                            name.green().bold()
                        );
                    }
                }
            }
        }

        if let Some(hosts_array) = self.doc.get("hosts").and_then(|v| v.as_array_of_tables()) {
            for table in hosts_array.iter() {
                let host_name = table.get("name").and_then(|v| v.as_str()).unwrap_or("");
                if let Some(users_val) = table.get("users") {
                    if let Some(users_array) = users_val.as_array() {
                        for val in users_array.iter() {
                            let user_name = val.as_str().ok_or_else(|| {
                                anyhow::anyhow!(
                                    "{}: non-string value in host '{}' users list",
                                    "invalid document structure".yellow().bold(),
                                    host_name.cyan().bold()
                                )
                            })?;
                            if !user_names.contains(user_name) {
                                anyhow::bail!(
                                    "{}: host '{}' assigns user '{}' which is not defined in the global user list",
                                    "validation error".red().bold(),
                                    host_name.cyan().bold(),
                                    user_name.green().bold()
                                );
                            }
                        }
                    } else {
                        anyhow::bail!(
                            "{}: 'users' field for host '{}' is not an array",
                            "invalid document structure".yellow().bold(),
                            host_name.cyan().bold()
                        );
                    }
                }
            }
        }

        Ok(())
    }

    /// Reads and parses the manifest.toml file from the workspace directory.
    pub fn from_workspace<P: AsRef<std::path::Path>>(workspace: P) -> anyhow::Result<Self> {
        let manifest_path = workspace.as_ref().join("manifest.toml");
        
        let file = std::fs::OpenOptions::new()
            .read(true)
            .open(&manifest_path)
            .map_err(|e| anyhow::anyhow!("{}: {}", "system error".red().bold(), e))?;
            
        let lock = fd_lock::RwLock::new(file);
        let guard = lock.read().map_err(|e| anyhow::anyhow!("{}: failed to lock manifest.toml: {}", "system error".red().bold(), e))?;
        
        let mut content = String::new();
        use std::io::Read;
        (&*guard).read_to_string(&mut content)
            .map_err(|e| anyhow::anyhow!("{}: {}", "system error".red().bold(), e))?;
            
        Self::from_str(&content)
    }

    /// Persists the manifest back to `manifest.toml` in the workspace directory.
    pub fn save<P: AsRef<std::path::Path>>(&self, workspace: P) -> anyhow::Result<()> {
        let manifest_path = workspace.as_ref().join("manifest.toml");
        
        #[allow(clippy::suspicious_open_options)]
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .open(&manifest_path)
            .map_err(|e| anyhow::anyhow!("{}: {}", "system error".red().bold(), e))?;
            
        let mut lock = fd_lock::RwLock::new(file);
        let mut guard = lock.write().map_err(|e| anyhow::anyhow!("{}: failed to lock manifest.toml: {}", "system error".red().bold(), e))?;
        
        use std::io::{Seek, Write};
        let f = &mut *guard;
        f.rewind().map_err(|e| anyhow::anyhow!("{}: {}", "system error".red().bold(), e))?;
        f.set_len(0).map_err(|e| anyhow::anyhow!("{}: {}", "system error".red().bold(), e))?;
        f.write_all(self.doc.to_string().as_bytes())
            .map_err(|e| anyhow::anyhow!("{}: {}", "system error".red().bold(), e))?;
            
        Ok(())
    }

    /// Returns whether the manifest has been mutated since loading.
    pub fn is_dirty(&self) -> bool {
        self.dirty
    }
}

impl FromStr for Manifest {
    type Err = anyhow::Error;

    fn from_str(content: &str) -> Result<Self, Self::Err> {
        let doc = DocumentMut::from_str(content)
            .map_err(|e| {
                anyhow::anyhow!(
                    "{}: {}",
                    "invalid document structure".yellow().bold(),
                    e
                )
            })?;

        // Validate hosts structure
        if let Some(hosts_array) = doc.get("hosts").and_then(|v| v.as_array_of_tables()) {
            for table in hosts_array.iter() {
                let _name = table
                    .get("name")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| {
                        anyhow::anyhow!(
                            "{}: {}",
                            "invalid document structure".yellow().bold(),
                            "missing host name"
                        )
                    })?;
            }
        }

        // Validate users structure
        if let Some(users_array) = doc.get("users").and_then(|v| v.as_array_of_tables()) {
            for table in users_array.iter() {
                let _name = table
                    .get("name")
                    .and_then(|v| v.as_str())
                    .ok_or_else(|| {
                        anyhow::anyhow!(
                            "{}: {}",
                            "invalid document structure".yellow().bold(),
                            "missing user name"
                        )
                    })?;
            }
        }

        Ok(Manifest { doc, dirty: false })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_host_and_user() {
        let current_host = get_current_hostname().unwrap_or_default();
        let current_user = std::env::var("USER").unwrap_or_default();
        let toml_content = format!(
            r#"
            [[hosts]]
            name = "host1"
            users = ["user1"]

            [[hosts]]
            name = "{}"
            users = ["user1"]

            [[users]]
            name = "user1"

            [[users]]
            name = "{}"
            "#,
            current_host, current_user
        );
        let manifest = Manifest::from_str(&toml_content).unwrap();

        // check_host tests
        assert_eq!(manifest.check_host("host1"), Some(Cow::Borrowed("host1")));
        assert_eq!(manifest.check_host("invalid-host"), None);
        // resolving empty host
        let resolved_host = manifest.check_host("");
        assert!(resolved_host.is_some());
        assert_eq!(
            resolved_host.unwrap().as_ref(),
            &get_current_hostname().unwrap()
        );

        // check_user tests
        assert_eq!(manifest.check_user("user1"), Some(Cow::Borrowed("user1")));
        assert_eq!(manifest.check_user("invalid-user"), None);
        // resolving empty user
        let resolved_user = manifest.check_user("");
        assert!(resolved_user.is_some());
        assert_eq!(
            resolved_user.unwrap().as_ref(),
            &std::env::var("USER").unwrap()
        );
    }

    #[test]
    fn test_load_manifest_from_toml() {
        let toml_content = r#"
            [[hosts]]
            name = "nihilicht-sagittarius"
            arch = "x86_64-linux"
            users = ["tsukuyomi"]

            [[users]]
            name = "tsukuyomi"
        "#;
        let manifest = Manifest::from_str(toml_content).unwrap();
        assert_eq!(
            manifest.check_host("nihilicht-sagittarius"),
            Some(Cow::Borrowed("nihilicht-sagittarius"))
        );
        assert_eq!(
            manifest.check_user("tsukuyomi"),
            Some(Cow::Borrowed("tsukuyomi"))
        );
    }

    #[test]
    fn test_list_functions() {
        let toml_content = r#"
            [[hosts]]
            name = "host-a"
            users = ["user-1", "user-2"]

            [[hosts]]
            name = "host-b"
            users = []

            [[users]]
            name = "user-1"

            [[users]]
            name = "user-2"
        "#;
        let manifest = Manifest::from_str(toml_content).unwrap();

        assert_eq!(manifest.list_hosts(), vec!["host-a", "host-b"]);
        assert_eq!(manifest.list_users(), vec!["user-1", "user-2"]);
        assert_eq!(manifest.list_users_for_host("host-a"), Some(vec!["user-1", "user-2"]));
        assert_eq!(manifest.list_users_for_host("host-b"), Some(vec![]));
        assert_eq!(manifest.list_users_for_host("non-existent-host"), None);
    }

    #[test]
    fn test_mutation_functions() {
        let toml_content = r#"
            [[hosts]]
            name = "host-a"
            users = ["user-1"]

            [[users]]
            name = "user-1"
        "#;
        let mut manifest = Manifest::from_str(toml_content).unwrap();

        // 1. Test add_host
        manifest.add_host("host-b", "x86_64-linux").unwrap();
        assert_eq!(manifest.list_hosts(), vec!["host-a", "host-b"]);
        assert_eq!(
            manifest.add_host("host-a", "x86_64-linux").unwrap_err().to_string(),
            format!("host '{}' already exists", "host-a".cyan().bold())
        );

        // 2. Test sub_host
        manifest.sub_host("host-a").unwrap();
        assert_eq!(manifest.list_hosts(), vec!["host-b"]);
        assert_eq!(
            manifest.sub_host("host-a").unwrap_err().to_string(),
            format!("host '{}' not found", "host-a".cyan().bold())
        );

        // 3. Test add_user
        manifest.add_user("user-2").unwrap();
        assert_eq!(manifest.list_users(), vec!["user-1", "user-2"]);
        assert_eq!(
            manifest.add_user("user-1").unwrap_err().to_string(),
            format!("user '{}' already exists", "user-1".green().bold())
        );

        // 4. Test sub_user
        manifest.sub_user("user-1").unwrap();
        assert_eq!(manifest.list_users(), vec!["user-2"]);
        assert_eq!(
            manifest.sub_user("user-1").unwrap_err().to_string(),
            format!("user '{}' not found", "user-1".green().bold())
        );

        // 5. Test add_user_to_host
        assert_eq!(
            manifest.add_user_to_host("host-b", "user-1").unwrap_err().to_string(),
            format!("user '{}' not found", "user-1".green().bold())
        );
        manifest.add_user_to_host("host-b", "user-2").unwrap();
        assert_eq!(manifest.list_users_for_host("host-b"), Some(vec!["user-2"]));
        assert_eq!(
            manifest.add_user_to_host("host-b", "user-2").unwrap_err().to_string(),
            format!(
                "user '{}' is already assigned to host '{}'",
                "user-2".green().bold(),
                "host-b".cyan().bold()
            )
        );

        // 6. Test sub_user_from_host
        assert_eq!(
            manifest.sub_user_from_host("host-b", "user-1").unwrap_err().to_string(),
            format!("user '{}' not found", "user-1".green().bold())
        );
        manifest.sub_user_from_host("host-b", "user-2").unwrap();
        assert_eq!(manifest.list_users_for_host("host-b"), Some(vec![]));
        assert_eq!(
            manifest.sub_user_from_host("host-b", "user-2").unwrap_err().to_string(),
            format!(
                "user '{}' is not assigned to host '{}'",
                "user-2".green().bold(),
                "host-b".cyan().bold()
            )
        );
    }

    #[test]
    fn test_verify() {
        // Sound manifest
        let sound_content = r#"
            [[hosts]]
            name = "host-a"
            users = ["user-1"]

            [[users]]
            name = "user-1"
        "#;
        let manifest = Manifest::from_str(sound_content).unwrap();
        assert!(manifest.verify().is_ok());

        // Duplicate host name
        let duplicate_host_content = r#"
            [[hosts]]
            name = "host-a"

            [[hosts]]
            name = "host-a"
        "#;
        let manifest = Manifest::from_str(duplicate_host_content).unwrap();
        let err = manifest.verify().unwrap_err().to_string();
        assert!(err.contains("duplicate host name"));

        // Duplicate user name
        let duplicate_user_content = r#"
            [[users]]
            name = "user-1"

            [[users]]
            name = "user-1"
        "#;
        let manifest = Manifest::from_str(duplicate_user_content).unwrap();
        let err = manifest.verify().unwrap_err().to_string();
        assert!(err.contains("duplicate user name"));

        // Referential integrity failure (user not defined)
        let integrity_failure_content = r#"
            [[hosts]]
            name = "host-a"
            users = ["user-2"]

            [[users]]
            name = "user-1"
        "#;
        let manifest = Manifest::from_str(integrity_failure_content).unwrap();
        let err = manifest.verify().unwrap_err().to_string();
        assert!(err.contains("not defined in the global user list"));

        // Invalid home type validation
        let invalid_home_content = r#"
            [[users]]
            name = "user-1"
            home = "not-a-bool"
        "#;
        let manifest = Manifest::from_str(invalid_home_content).unwrap();
        let err = manifest.verify().unwrap_err().to_string();
        assert!(err.contains("is not a boolean"));

        // Invalid groups type validation
        let invalid_groups_content = r#"
            [[users]]
            name = "user-1"
            groups = "not-an-array"
        "#;
        let manifest = Manifest::from_str(invalid_groups_content).unwrap();
        let err = manifest.verify().unwrap_err().to_string();
        assert!(err.contains("is not an array"));

        // Invalid groups items validation
        let invalid_groups_items_content = r#"
            [[users]]
            name = "user-1"
            groups = [123]
        "#;
        let manifest = Manifest::from_str(invalid_groups_items_content).unwrap();
        let err = manifest.verify().unwrap_err().to_string();
        assert!(err.contains("non-string value in user"));

        // Sound manifest with home and groups
        let sound_full_content = r#"
            [[users]]
            name = "user-1"
            home = true
            groups = ["wheel", "networkmanager"]
        "#;
        let manifest = Manifest::from_str(sound_full_content).unwrap();
        assert!(manifest.verify().is_ok());
    }
}
