use i30ltz_core::config::I30Config;
use std::path::PathBuf;
const CONFIG: &str = include_str!("../../../config/i30ltz.toml");

#[test]
fn shipped_config_matches_defaults() {
    let config = I30Config::from_toml(CONFIG).unwrap();
    assert_eq!(config.data_dir, I30Config::default().data_dir);
    assert_eq!(config.ai.context_size, 4096);
}

#[test]
fn malformed_config_is_rejected() {
    assert!(I30Config::from_toml("broken = [").is_err());
}

#[test]
fn invalid_values_are_rejected() {
    for (from, to) in [
        ("threads      = 4", "threads      = 0"),
        ("context_size = 4096", "context_size = 0"),
        ("gpu_layers   = 0", "gpu_layers   = -1"),
        ("#cc1a1a", "bad-red"),
        (r#"log_level  = "info""#, r#"log_level  = "invalid""#),
    ] {
        let changed = CONFIG.replace(from, to);
        assert_ne!(changed, CONFIG, "test pattern must match");
        assert!(I30Config::from_toml(&changed).is_err());
    }
}

#[test]
fn relative_data_path_is_rejected() {
    assert!(I30Config::from_toml(&CONFIG.replace("/var/lib/i30ltz", "relative")).is_err());
}

#[test]
fn absent_config_uses_defaults() {
    let absent = PathBuf::from(format!("/nonexistent-i30ltz-{}", uuid::Uuid::new_v4()));
    assert_eq!(I30Config::from_paths(&[absent]).unwrap().log_level, "info");
}

#[test]
fn explicit_missing_config_is_an_error() {
    let absent = PathBuf::from(format!("/nonexistent-i30ltz-{}", uuid::Uuid::new_v4()));
    assert!(I30Config::from_file(&absent).is_err());
}
