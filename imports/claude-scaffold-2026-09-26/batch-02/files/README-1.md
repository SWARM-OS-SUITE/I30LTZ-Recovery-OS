# i30LTZ Recovery OS
**v0.1.0 | 2026-09-26 | Debian 12 (Bookworm)**
Creator: I320K3-N-I30LTZ  |  AI: Dr. I30LTZ (MAD IT)

---

Enterprise forensic PC repair & data recovery OS.
100% native compiled binaries — no Electron, no web wrapper, bare metal.

## Quick Start (Debian 12)

```bash
sudo bash scripts/install-build-deps.sh  # root — installs all deps + llama.cpp
make dev                                  # fast dev build
make release                              # stripped release build
sudo make install                         # deploy to /opt/i30ltz
i30ltz                                    # launch
```

## Make Commands

| Command | What |
|---------|------|
| `make dev` | Build all (dev, fast) |
| `make release` | Build all (release, stripped, LTO) |
| `make shell` | Only: Slint OS shell |
| `make mad-it` | Only: MAD IT AI core |
| `make case-manager` | Only: i30cm TUI |
| `make check` | Cargo check only |
| `make clippy` | Lint all |
| `make fmt` | Format all |
| `make test` | Unit tests |
| `sudo make install` | Deploy to /opt/i30ltz |
| `make clean` | Remove artifacts |

## Build Order

| Step | Target | Status |
|------|--------|--------|
| D | Workspace scaffold | DONE |
| A | apps/shell — Slint UI | NEXT |
| C | apps/case-manager — i30cm TUI | |
| B | apps/mad-it — MAD IT AI | |
