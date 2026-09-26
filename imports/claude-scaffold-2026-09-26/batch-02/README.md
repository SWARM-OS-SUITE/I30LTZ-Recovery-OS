# Second recovered download batch — 2026-09-26

All 28 supplied files are preserved unchanged under `files/`, with SHA-256 hashes,
source categories, duplicate relationships and check results in `manifest.json`.
The 28-download count does not mean the earlier 28-file native scaffold is complete:
this selection includes repeated originals and files from other project designs.

## Inventory

- Native Rust/Debian scaffold: `Cargo-1.toml` is the workspace-root manifest,
  `README-1.md` its guide, and `version.rs` supplies a formerly missing core module.
  The previous source/config/Makefile files remain unchanged.
- Debian web UI: `README.md`, `i30ltz-setup.sh`, `home.html` and the HTML splash.
  This is a distinct browser-based design from the native Slint scaffold.
- Android companion: AndroidManifest, editor HTML, resource XML files and icons.
  These are not replacements for the current phone app. In particular, strings.xml
  uses the older SWARM_OS Companion label. Some resources match existing files.
- `install-build-deps.sh`, `install-build-deps (1).sh`, and
  `install-build-deps-1.sh` are byte-identical copies.

## Still needed for native integration

`logger.rs` is still missing. Each workspace member needs its Cargo.toml and source
files, with its original directory structure:

- `apps/shell`
- `apps/mad-it`
- `apps/case-manager`
- `apps/hardware-dash`
- `libs/i30ltz-core`
- `libs/i30ltz-ui`
- `tools/drive-scan`
- `tools/report-gen`

Please supply the original scaffold ZIP or these directories. No placeholder apps
or guessed crate manifests have been created to make an incomplete build appear
successful. The active raylib application and Android app remain unchanged.

## Validation boundary

Every copy matches its source hash. All five shell downloads pass `bash -n`, both
TOML documents parse, and all ten XML documents are well-formed. A basic scan
found no common credential patterns; it is not an exhaustive security audit.
No installer or launcher was executed. No native/Android build or Debian boot
is claimed. HTML runtime behavior has not been verified.
