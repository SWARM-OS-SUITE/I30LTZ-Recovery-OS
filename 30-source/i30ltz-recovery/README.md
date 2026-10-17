# I30LTZ Recovery OS

> **Suite map:** SWARM_OS + LUCILLE (LLcy) = **Arch**, on the **internal** drive.
> I30LTZ Recovery OS + Dr. I30LTZ "MAD AI" = **Ubuntu**, on an **external** drive,
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


## Recovery console UI (remade 2026-10-12)
Enterprise layout (the earlier red UGA-bulldog / carbon-fibre look is gone): top bar, left navigation, five pages:
Overview, Drives & partitions (real `lsblk` data, SMART health when `smartctl` works), Recovery tools (SMART report,
ddrescue command, read-only filesystem check, TestDisk, PhotoRec, GParted: each opens only on a click, in its own window),
System & services, MAD AI assistant (chat). Code: `src/ui.rs` (palette, fonts, widgets), `src/main.rs` (pages),
`src/eval.rs` (data). Build: `CARGO_HOME=/mnt/recoverybuild/25-toolchain/cargo-home cargo build --release --locked`.
Dev aids: `I30LTZ_START_PAGE=1..5` opens a page; `I30LTZ_SHOT=file.png` saves a framebuffer screenshot and exits.
Verified: compiles, launches, all five pages render with real data on the dev PC. NOT verified: the recovery tool launches
(testdisk/photorec/smartctl/ddrescue are not installed on the dev PC), the SMART column, and the chat against the ISO's brain service.
