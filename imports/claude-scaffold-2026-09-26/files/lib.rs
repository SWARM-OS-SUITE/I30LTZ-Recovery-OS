//! i30LTZ Core Library
//! v0.1.0 | 2026-09-26 | Debian 12
//!
//! Shared types, config loading, logging init, DB connection,
//! and error types used by every crate in the workspace.

pub mod config;
pub mod db;
pub mod error;
pub mod logger;
pub mod models;
pub mod version;

pub use error::{I30Error, Result};
