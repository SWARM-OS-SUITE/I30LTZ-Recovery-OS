//! Shared theme values. Slint components belong to the next UI milestone.
pub use i30ltz_core::config::ThemeConfig;
pub fn default_theme() -> ThemeConfig {
    i30ltz_core::config::I30Config::default().theme
}
