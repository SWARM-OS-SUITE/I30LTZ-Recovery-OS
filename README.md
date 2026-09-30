# I30LTZ Recovery OS

- **Reconstructed Debian-targeted Rust foundation:** [`native/README.md`](native/README.md).
  Run `make -C native dev`, `make -C native test`, and `make -C native smoke`.
- **Existing evaluation application:** root `Cargo.toml`, `build.rs`, and `src/`.
  Kept intact while the native workspace is developed.
- **Ubuntu first boot (secure setup, v1.0.0 · 2026-09-30):**
  [`system/ubuntu-first-boot/`](system/ubuntu-first-boot/README.md). Sets up
  SWARM_OS / LLcy and I30LTZ / MAD IT. Preview with `sudo ./first-boot.sh --dry-run`.
- **Original Claude downloads:** [`imports/claude-scaffold-2026-09-26/`](imports/claude-scaffold-2026-09-26/).
  Saved unchanged with hashes. They include distinct native, web UI and Android
  references; the reconstructed native workspace is the active scaffold path.
- **Cloud checkpoints:** see `CLAUDE.md`. Automatic checkpoints save work, but do
  not establish passing tests or completed app functionality.

Native Step D now has reconstructed manifests and core plumbing. Graphical shell,
case-manager features, inference, drive operations and an OS image are still pending.
