//! Honest entry points for the scaffold, before application features land.
use std::process::ExitCode;

pub fn run(binary: &str, purpose: &str) -> ExitCode {
    let args: Vec<_> = std::env::args().skip(1).collect();
    match args.as_slice() {
        [flag] if flag == "--version" => {
            println!("{binary}: {}", crate::version::version_string());
            ExitCode::SUCCESS
        }
        [flag] if flag == "--help" || flag == "-h" => {
            println!("{binary} — {purpose}\nWorkspace scaffold; application functionality is not implemented.\n\nOptions:\n  --version       Show build identity\n  --check-config  Validate configuration without changing the system\n  --help          Show this message");
            ExitCode::SUCCESS
        }
        [flag] if flag == "--check-config" => match crate::config::I30Config::load() {
            Ok(config) => {
                if let Err(e) = crate::logger::init(&config.log_level) {
                    eprintln!("logger initialization failed: {e}");
                    return ExitCode::FAILURE;
                }
                println!("Configuration valid. Application features are not implemented.");
                ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("Configuration error: {e}");
                ExitCode::FAILURE
            }
        },
        _ => {
            eprintln!("{purpose} is not implemented yet. Use {binary} --help for scaffold checks.");
            ExitCode::from(2)
        }
    }
}
