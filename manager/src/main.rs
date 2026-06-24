pub mod cli;
pub mod execution;
pub mod manifest;
pub mod context;

use clap::Parser;
use cli::Cli;
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::FmtSubscriber;

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    let level = match cli.verbose {
        0 => LevelFilter::WARN,
        1 => LevelFilter::INFO,
        2 => LevelFilter::DEBUG,
        _ => LevelFilter::TRACE,
    };

    let subscriber = FmtSubscriber::builder()
        .with_max_level(level)
        .with_target(false)
        .with_thread_ids(false)
        .with_thread_names(false)
        .without_time()
        .finish();

    tracing::subscriber::set_global_default(subscriber)
        .expect("failed to set global subscriber");

    tracing::info!("Workspace: {:?}", cli.workspace);

    cli.exec()
}
