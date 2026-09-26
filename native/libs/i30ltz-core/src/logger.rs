//! Shared logger; explicit I30LTZ_LOG takes precedence over config log_level.
pub fn init(default_level: &str) -> Result<(), log::SetLoggerError> {
    env_logger::Builder::from_env(env_logger::Env::default().filter_or("I30LTZ_LOG", default_level))
        .try_init()
}
