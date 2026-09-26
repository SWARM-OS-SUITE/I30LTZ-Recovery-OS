//! i30LTZ unified error type.

use thiserror::Error;

pub type Result<T> = std::result::Result<T, I30Error>;

#[derive(Debug, Error)]
pub enum I30Error {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Database error: {0}")]
    Db(#[from] rusqlite::Error),

    #[error("Serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("Config error: {0}")]
    Config(String),

    #[error("Drive error: {0}")]
    Drive(String),

    #[error("AI/inference error: {0}")]
    Ai(String),

    #[error("Case error: {0}")]
    Case(String),

    #[error("{0}")]
    Other(#[from] anyhow::Error),
}
