//! Build-time version constants — stamped on every binary and UI surface.

pub const OS_NAME: &str = "i30LTZ Recovery OS";
pub const APP_NAME: &str = "i30LTZ";
pub const VERSION: &str = "0.1.0";
pub const BUILD_DATE: &str = "2026-09-26";
pub const BASE_OS: &str = "Debian 12 (Bookworm)";
pub const CREATOR: &str = "I320K3-N-I30LTZ";
pub const AI_NAME: &str = "Dr. I30LTZ (MAD IT)";

pub fn version_string() -> String {
    format!("{} v{} | {} | {}", APP_NAME, VERSION, BUILD_DATE, BASE_OS)
}
