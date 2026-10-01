# I30LTZ Recovery OS

> **Suite map (one PC, ThinkPad X13):** SWARM_OS + LUCILLE (LLcy) = **Arch** on the
> **internal NVMe**. I30LTZ Recovery OS + Dr. I30LTZ "MAD IT" = **Ubuntu** on the
> external drive **boltz**. It repairs the PC, reaches Lucille, and **builds SWARM_OS**.
> Full details: [`docs/SUITE_ARCHITECTURE.md`](docs/SUITE_ARCHITECTURE.md).

- **Reconstructed Debian-targeted Rust foundation:** [`native/README.md`](native/README.md).
  Run `make -C native dev`, `make -C native test`, and `make -C native smoke`.
- **Existing evaluation application:** root `Cargo.toml`, `build.rs`, and `src/`.
  Kept intact while the native workspace is developed.
- **Recovery OS first-boot kit (secure setup + SWARM_OS builder, v2.1.0 · 2026-10-01):**
  [`system/`](system/README.md). Run it on the fresh Ubuntu install on boltz.
- **Original Claude downloads:** [`imports/claude-scaffold-2026-09-26/`](imports/claude-scaffold-2026-09-26/).
  Saved unchanged with hashes. They include distinct native, web UI and Android
  references; the reconstructed native workspace is the active scaffold path.
- **Cloud checkpoints:** see `CLAUDE.md`. Automatic checkpoints save work, but do
  not establish passing tests or completed app functionality.

Native Step D now has reconstructed manifests and core plumbing. Graphical shell,
case-manager features, inference, drive operations and an OS image are still pending.
