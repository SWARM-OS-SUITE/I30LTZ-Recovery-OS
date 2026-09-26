# Recovered Claude scaffold files — 2026-09-26

Nine original files supplied by the user have been preserved byte-for-byte in
`files/`; SHA-256 hashes and sizes are recorded in `manifest.json`. This is an
incomplete import, not a replacement for the existing Recovery OS application.
The supplied headers describe a Debian 12 scaffold. No OS migration is performed.

## Missing inputs

The chat screenshot describes 28 files; only nine were supplied here. The new
workspace `Cargo.toml`, README, crate manifests and application source directories
are not included. `lib.rs` declares `logger` and `version` modules whose files are
missing. The Makefile names six absent packages: `i30ltz-shell`, `mad-it`,
`i30ltz-case-manager`, `i30ltz-hardware-dash`, `drivescan`, and `reportgen`.

Please obtain the remaining original files, ideally as a ZIP preserving paths.
The standalone downloads do not establish their intended crate directory layout.
The existing root Cargo.toml belongs to the older raylib application and cannot
serve as the manifest for this scaffold without deliberate integration work.

## Checks and integration notes

- All nine copies match their original SHA-256 hashes.
- Both shell files passed `bash -n`; they were not executed.
- `i30ltz.toml` parses as TOML.
- Rust compilation is blocked by missing manifests/modules/crates.
- `config.rs` ignores the launcher's `I30LTZ_CONFIG` environment override.
- The launcher assumes writable system log/data directories and an installed
  `i30ltz-shell` binary that is not supplied.
- The dependency installer changes system packages and builds downloaded code;
  it requires a Debian target and further review before execution.

Original contents remain unchanged so corrections can be reviewed separately
when the rest of the scaffold is available.

## Second batch update

See `batch-02/README.md`: the workspace-root manifest and version.rs have now
been recovered there. Logger, member manifests and application/library/tool
directories remain missing. The first batch above is retained unchanged.
