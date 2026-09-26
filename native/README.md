# I30LTZ Recovery OS — reconstructed native workspace

This is **Step D: the buildable foundation**, reconstructed on 2026-09-26 from
the user's saved Claude downloads and screenshots. The original files remain
unchanged in `../imports/claude-scaffold-2026-09-26/`. Missing files here are new
implementation, not recovered original code. The previous raylib application
remains at the repository root; this workspace is deliberately independent.

## Build and check

Run as your normal user from this directory, with Cargo/Rust and a C compiler:

```sh
make dev
make test
make clippy
make smoke
```

`Cargo.lock` records resolved dependencies and the Makefile uses `--locked`.
The Debian 12 target requires a current Rust toolchain; the distribution's stock
compiler may be too old. `sudo bash scripts/install-build-deps.sh` installs only
system compiler tools on Debian 12, not Rust, Slint, llama.cpp or the OS itself.
Do not run the original archived installer as part of this build.

## Implemented foundation

- Eight Cargo member manifests and source targets matching the supplied layout.
- Core domain types, version constants and unified errors from the downloads.
- Configuration precedence: explicit `I30LTZ_CONFIG`, user XDG config, system
  config, then compiled defaults. Explicit invalid/missing config fails clearly.
- Validation for configuration paths, AI numeric limits, log level and theme colors.
- Logging initialization using `I30LTZ_LOG` or the configured default.
- SQLite schema creation, repeatable initialization, busy timeout and foreign keys.
- Shared theme values. No Slint renderer or component library exists yet.
- Six scaffold command entry points with `--help`, `--version`, `--check-config`.
  Unsupported/no-argument invocation returns status 2 and says not implemented.

## Remaining application milestones

| Member | Binary | Status |
|---|---|---|
| apps/shell | i30ltz-shell | Entry point only; graphical Slint shell is next |
| apps/case-manager | i30cm | Entry point only; case CRUD/TUI not implemented |
| apps/mad-it | mad-it | Entry point only; llama.cpp inference not implemented |
| apps/hardware-dash | i30ltz-hwdash | Entry point only; hardware UI not implemented |
| tools/drive-scan | drivescan | Entry point only; SMART/device inspection not implemented |
| tools/report-gen | reportgen | Entry point only; Markdown/PDF export not implemented |
| libs/i30ltz-core | library | Config, models, schema, errors, logging and version |
| libs/i30ltz-ui | library | Theme values only; Slint components not implemented |

The supplied roadmap orders subsequent work A (shell), C (case manager), B (AI).
No bootable Recovery OS image, native GUI, AI inference or recovery operation is
provided by this scaffold. Debian remains the intended base; a host build does
not establish Debian compatibility or successful boot.

## Installation and launcher

`make install DESTDIR=/absolute/staging/path` builds release artifacts and stages
binaries under `opt/i30ltz/bin`, configuration under `opt/i30ltz/config`, and the
launcher under `usr/local/bin`. Existing configuration is preserved. `make
uninstall` removes only named binaries and launcher, leaving configuration/data.
This installs scaffold commands, not an operational desktop or system service.

Default prefix is `/opt/i30ltz`. For a custom prefix, set `PREFIX` during install
and `I30LTZ_PREFIX` when invoking the launcher. For staging smoke checks:

```sh
I30LTZ_PREFIX=/absolute/staging/path/opt/i30ltz /absolute/staging/path/usr/local/bin/i30ltz --version
```

The launcher creates no privileged log/data directories and forwards arguments.
`--check-config` validates settings only; it does not initialize a database,
load models, access drives, or verify application readiness.

## Verified on the development host (2026-09-26)

Eight workspace members build in development and release mode. Eight core tests
and 42 executable CLI checks pass; formatting, all-target checks and Clippy
with warnings denied pass. A temporary staged release install, launcher version/
config checks, reinstall configuration preservation and scoped uninstall pass.
Original import hashes remain unchanged. No Debian VM/hardware boot or GUI test
was performed. `make install-check` repeats the nonprivileged staged-install test.
Visual references are saved in `design/README.md` and `design/reference/`.
