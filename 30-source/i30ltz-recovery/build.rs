fn main() {
    // Bake the build date and timestamp into the binary at compile time.
    // Accessed in main.rs via env!("BUILD_DATE") and env!("BUILD_TS").
    let date = std::process::Command::new("date")
        .args(["+%Y-%m-%d"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_else(|| "unknown".to_string());

    let ts = std::process::Command::new("date")
        .args(["+%Y-%m-%d %H:%M"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_else(|| "unknown".to_string());

    println!("cargo:rustc-env=BUILD_DATE={}", date.trim());
    println!("cargo:rustc-env=BUILD_TS={}", ts.trim());
    // Rerun if source files change (cargo handles this by default for src/)
    println!("cargo:rerun-if-changed=build.rs");
}
