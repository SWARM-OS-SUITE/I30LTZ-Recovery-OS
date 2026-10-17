
// [FIX-2026-10-06] version stamp
const I30LTZ_VERSION: &str = "v0.2.0-alpha";
const I30LTZ_BUILD_DATE: &str = "2026-10-06";

fn main() -> std::process::ExitCode {
    i30ltz_core::cli::run("i30cm", "Recovery case manager")
}
