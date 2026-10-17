//! i30LTZ global configuration — loaded from /opt/i30ltz/config/i30ltz.toml
//! or ~/.config/i30ltz/i30ltz.toml (field mode).

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct I30Config {
    pub data_dir: PathBuf,
    pub cases_dir: PathBuf,
    pub models_dir: PathBuf,
    pub log_level: String,
    pub ai: AiConfig,
    pub theme: ThemeConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiConfig {
    pub model_file: PathBuf,
    pub context_size: usize,
    pub threads: usize,
    pub gpu_layers: i32, // 0 = CPU-only
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemeConfig {
    pub accent_red: String,
    pub accent_yellow: String,
    pub bg_void: String,
}

impl Default for I30Config {
    fn default() -> Self {
        Self {
            data_dir: PathBuf::from("/var/lib/i30ltz"),
            cases_dir: PathBuf::from("/var/lib/i30ltz/cases"),
            models_dir: PathBuf::from("/opt/i30ltz/models"),
            log_level: "info".into(),
            ai: AiConfig {
                model_file: PathBuf::from("/opt/i30ltz/models/mad-it.gguf"),
                context_size: 4096,
                threads: 4,
                gpu_layers: 0,
            },
            theme: ThemeConfig {
                accent_red: "#cc1a1a".into(),
                accent_yellow: "#f0c020".into(),
                bg_void: "#050508".into(),
            },
        }
    }
}

impl I30Config {
    /// Explicit override, user config, system config, then compiled defaults.
    /// A supplied but unreadable/invalid override is an error, never a fallback.
    pub fn load() -> crate::Result<Self> {
        if let Some(path) = std::env::var_os("I30LTZ_CONFIG") {
            if path.is_empty() {
                return Err(crate::I30Error::Config("I30LTZ_CONFIG is empty".into()));
            }
            return Self::from_file(Path::new(&path));
        }
        let user_dir = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .filter(|p| p.is_absolute())
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")));
        let mut paths = Vec::new();
        if let Some(dir) = user_dir {
            paths.push(dir.join("i30ltz/i30ltz.toml"));
        }
        paths.push(PathBuf::from("/opt/i30ltz/config/i30ltz.toml"));
        Self::from_paths(&paths)
    }

    pub fn from_paths(paths: &[PathBuf]) -> crate::Result<Self> {
        for path in paths {
            match std::fs::read_to_string(path) {
                Ok(text) => return Self::from_toml(&text),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                Err(e) => return Err(e.into()),
            }
        }
        Ok(Self::default())
    }

    pub fn from_file(path: &Path) -> crate::Result<Self> {
        Self::from_toml(&std::fs::read_to_string(path)?)
    }

    pub fn from_toml(text: &str) -> crate::Result<Self> {
        let config: Self =
            toml::from_str(text).map_err(|e| crate::I30Error::Config(e.to_string()))?;
        if config.ai.context_size == 0 || config.ai.threads == 0 || config.ai.gpu_layers < 0 {
            return Err(crate::I30Error::Config(
                "AI context/threads must be positive; gpu_layers must be nonnegative".into(),
            ));
        }
        for path in [
            &config.data_dir,
            &config.cases_dir,
            &config.models_dir,
            &config.ai.model_file,
        ] {
            if !path.is_absolute() {
                return Err(crate::I30Error::Config(
                    "configured paths must be absolute".into(),
                ));
            }
        }
        config
            .log_level
            .parse::<log::LevelFilter>()
            .map_err(|_| crate::I30Error::Config("invalid log_level".into()))?;
        for color in [
            &config.theme.accent_red,
            &config.theme.accent_yellow,
            &config.theme.bg_void,
        ] {
            if color.len() != 7
                || !color.starts_with('#')
                || !color[1..].bytes().all(|b| b.is_ascii_hexdigit())
            {
                return Err(crate::I30Error::Config(
                    "theme colors must use #RRGGBB".into(),
                ));
            }
        }
        Ok(config)
    }
}
