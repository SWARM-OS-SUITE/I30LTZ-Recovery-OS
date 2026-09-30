# I30LTZ Recovery OS

> **Suite map:** SWARM_OS + LUCILLE (LLcy) = **Arch**, on the **internal** drive.
> I30LTZ Recovery OS + Dr. I30LTZ "MAD IT" = **Ubuntu**, on an **external** drive,
> and it can reach Lucille. Full details: [`docs/SUITE_ARCHITECTURE.md`](docs/SUITE_ARCHITECTURE.md).

- **Reconstructed Debian-targeted Rust foundation:** [`native/README.md`](native/README.md).
  Run `make -C native dev`, `make -C native test`, and `make -C native smoke`.
- **Existing evaluation application:** root `Cargo.toml`, `build.rs`, and `src/`.
  Kept intact while the native workspace is developed.
- **First-boot kits (secure setup, v2.0.0 · 2026-09-30):** [`system/`](system/README.md).
  There's one kit per machine: I30LTZ Recovery OS, or the dev workstation that
  builds both OSes. SWARM_OS is a separate OS, and its kit lives in the SWARM_OS repo.
- **Original Claude downloads:** [`imports/claude-scaffold-2026-09-26/`](imports/claude-scaffold-2026-09-26/).
  Saved unchanged with hashes. They include distinct native, web UI and Android
  references; the reconstructed native workspace is the active scaffold path.
- **Cloud checkpoints:** see `CLAUDE.md`. Automatic checkpoints save work, but do
  not establish passing tests or completed app functionality.

Native Step D now has reconstructed manifests and core plumbing. Graphical shell,
case-manager features, inference, drive operations and an OS image are still pending.
