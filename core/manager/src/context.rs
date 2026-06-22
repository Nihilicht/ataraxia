use std::path::Path;

pub trait Context {
    fn get_current_hostname(&self) -> anyhow::Result<String>;
    fn get_current_user(&self) -> anyhow::Result<String>;
    fn is_root(&self) -> bool;
    fn read_link(&self, path: &Path) -> std::io::Result<std::path::PathBuf>;
    
    /// Run a command and stream output to stdout/stderr
    fn run_command(&self, program: &str, args: &[&str], cwd: &Path, dry_run: bool) -> anyhow::Result<()>;
    
    /// Run a command and return its stdout as a string
    fn run_command_with_output(&self, program: &str, args: &[&str], cwd: &Path) -> anyhow::Result<String>;
}

pub struct RealContext;

impl Context for RealContext {
    fn get_current_hostname(&self) -> anyhow::Result<String> {
        nix::unistd::gethostname()
            .map(|h| h.to_string_lossy().into_owned())
            .map_err(|e| anyhow::anyhow!("failed to get hostname: {}", e))
    }

    fn get_current_user(&self) -> anyhow::Result<String> {
        std::env::var("USER")
            .map_err(|e| anyhow::anyhow!("failed to get USER: {}", e))
    }

    fn is_root(&self) -> bool {
        nix::unistd::Uid::effective().is_root()
    }

    fn read_link(&self, path: &Path) -> std::io::Result<std::path::PathBuf> {
        std::fs::read_link(path)
    }

    fn run_command(&self, program: &str, args: &[&str], cwd: &Path, dry_run: bool) -> anyhow::Result<()> {
        use owo_colors::OwoColorize;
        let prefix = format!("{}", "?>".blue().bold());
        if args.is_empty() {
            println!("{} {}", prefix, program);
        } else {
            let display_args: Vec<String> = args
                .iter()
                .map(|arg| {
                    if arg.contains(char::is_whitespace) || arg.contains('"') || arg.contains('\\') {
                        let escaped = arg.replace('\\', "\\\\").replace('"', "\\\"");
                        format!("\"{}\"", escaped)
                    } else {
                        arg.to_string()
                    }
                })
                .collect();
            println!("{} {} {}", prefix, program, display_args.join(" "));
        }

        if !dry_run {
            duct::cmd(program, args)
                .dir(cwd)
                .run()
                .map_err(|e| anyhow::anyhow!("failed to execute command '{}': {}", program, e))?;
        }

        Ok(())
    }

    fn run_command_with_output(&self, program: &str, args: &[&str], cwd: &Path) -> anyhow::Result<String> {
        duct::cmd(program, args)
            .dir(cwd)
            .read()
            .map_err(|e| anyhow::anyhow!("failed to execute command '{}': {}", program, e))
    }
}

#[cfg(test)]
pub struct MockContext {
    pub hostname: String,
    pub user: String,
    pub root: bool,
    pub active_system: Option<String>,
    pub commands_run: std::sync::Mutex<Vec<String>>,
    pub command_outputs: std::collections::HashMap<String, String>,
}

#[cfg(test)]
impl MockContext {
    pub fn new(hostname: &str, user: &str, root: bool) -> Self {
        Self {
            hostname: hostname.to_string(),
            user: user.to_string(),
            root,
            active_system: None,
            commands_run: std::sync::Mutex::new(Vec::new()),
            command_outputs: std::collections::HashMap::new(),
        }
    }

    pub fn set_active_system(&mut self, sys: &str) {
        self.active_system = Some(sys.to_string());
    }

    pub fn mock_output(&mut self, cmd: &str, output: &str) {
        self.command_outputs.insert(cmd.to_string(), output.to_string());
    }
}

#[cfg(test)]
impl Context for MockContext {
    fn get_current_hostname(&self) -> anyhow::Result<String> {
        Ok(self.hostname.clone())
    }

    fn get_current_user(&self) -> anyhow::Result<String> {
        Ok(self.user.clone())
    }

    fn is_root(&self) -> bool {
        self.root
    }

    fn read_link(&self, _path: &Path) -> std::io::Result<std::path::PathBuf> {
        if let Some(sys) = &self.active_system {
            Ok(std::path::PathBuf::from(sys))
        } else {
            Err(std::io::Error::new(std::io::ErrorKind::NotFound, "no active system"))
        }
    }

    fn run_command(&self, program: &str, args: &[&str], _cwd: &Path, _dry_run: bool) -> anyhow::Result<()> {
        let mut cmd = vec![program.to_string()];
        cmd.extend(args.iter().map(|s| s.to_string()));
        let full_cmd = cmd.join(" ");
        self.commands_run.lock().unwrap().push(full_cmd);
        Ok(())
    }

    fn run_command_with_output(&self, program: &str, args: &[&str], _cwd: &Path) -> anyhow::Result<String> {
        let mut cmd = vec![program.to_string()];
        cmd.extend(args.iter().map(|s| s.to_string()));
        let full_cmd = cmd.join(" ");
        self.commands_run.lock().unwrap().push(full_cmd.clone());
        
        if let Some(output) = self.command_outputs.get(&full_cmd) {
            Ok(output.clone())
        } else {
            Ok("".to_string())
        }
    }
}
