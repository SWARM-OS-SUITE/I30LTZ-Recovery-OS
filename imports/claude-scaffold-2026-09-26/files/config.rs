//! i30LTZ global configuration — loaded from /opt/i30ltz/config/i30ltz.toml
//! or ~/.config/i30ltz/i30ltz.toml (field mode).

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct I30Config {
    pub data_dir:   PathBuf,
    pub cases_dir:  PathBuf,
    pub models_dir: PathBuf,
    pub log_level:  String,
    pub ai:         AiConfig,
    pub theme:      ThemeConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiConfig {
    pub model_file:   PathBuf,
    pub context_size: usize,
    pub threads:      usize,
    pub gpu_layers:   i32,    // 0 = CPU-only
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemeConfig {
    pub accent_red:    String,
    pub accent_yellow: String,
    pub bg_void:       String,
}

impl Default for I30Config {
    fn default() -> Self {
        Self {
            data_dir:   PathBuf::from("/var/lib/i30ltz"),
            cases_dir:  PathBuf::from("/var/lib/i30ltz/cases"),
            models_dir: PathBuf::from("/opt/i30ltz/models"),
            log_level:  "info".into(),
            ai: AiConfig {
                model_file:   PathBuf::from("/opt/i30ltz/models/mad-it.gguf"),
                context_size: 4096,
                threads:      4,
                gpu_layers:   0,
            },
            theme: ThemeConfig {
                accent_red:    "#cc1a1a".into(),
                accent_yellow: "#f0c020".into(),
                bg_void:       "#050508".into(),
            },
        }
    }
}

impl I30Config {
    pub fn load() -> crate::Result<Self> {
        let paths = [
            PathBuf::from("/opt/i30ltz/config/i30ltz.toml"),
            dirs_next(Some("i30ltz"), "i30ltz.toml"),
        ];
        for p in &paths {
            if p.exists() {
                let s = std::fs::read_to_string(p)?;
                let cfg: I30Config = toml::from_str(&s)
                    .map_err(|e| crate::error::I30Error::Config(e.to_string()))?;
                return Ok(cfg);
            }
        }
        Ok(Self::default())
    }
}

fn dirs_next(app: Option<&str>, file: &str) -> PathBuf {
    let base = std::env::var("HOME").unwrap_or_else(|_| "/root".into());
    let mut p = PathBuf::from(base);
    p.push(".config");
    if let Some(a) = app { p.push(a); }
    p.push(file);
    p
}
