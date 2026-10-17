# ============================================================
# i30LTZ Recovery OS — Master Makefile
# v0.1.0 | 2026-09-26 | Debian 12 (Bookworm)
# ============================================================

INSTALL_PREFIX  ?= /opt/i30ltz
BIN_DIR          = $(INSTALL_PREFIX)/bin
ASSETS_DIR       = $(INSTALL_PREFIX)/assets
CONFIG_DIR       = $(INSTALL_PREFIX)/config
DATA_DIR         = /var/lib/i30ltz

CARGO            = cargo
CARGO_FLAGS_REL  = --release
CARGO_FLAGS_DEV  =

TARGETS_BIN = \
    apps/shell/target/release/i30ltz-shell \
    apps/mad-it/target/release/mad-it \
    apps/case-manager/target/release/i30cm \
    apps/hardware-dash/target/release/i30ltz-hwdash \
    tools/drive-scan/target/release/drivescan \
    tools/report-gen/target/release/reportgen

.PHONY: all dev release install uninstall clean help \
        shell mad-it case-manager hardware-dash drive-scan report-gen \
        check fmt clippy test

# ── DEFAULT ─────────────────────────────────────────────────
all: release

# ── DEV BUILD ───────────────────────────────────────────────
dev:
	@echo "[ i30LTZ ] Building workspace (dev)..."
	$(CARGO) build --workspace $(CARGO_FLAGS_DEV)
	@echo "[ i30LTZ ] Dev build complete."

# ── RELEASE BUILD ───────────────────────────────────────────
release:
	@echo "[ i30LTZ ] Building workspace (release)..."
	$(CARGO) build --workspace $(CARGO_FLAGS_REL)
	@echo "[ i30LTZ ] Release build complete."

# ── INDIVIDUAL CRATE BUILDS ─────────────────────────────────
shell:
	$(CARGO) build -p i30ltz-shell $(CARGO_FLAGS_REL)

mad-it:
	$(CARGO) build -p mad-it $(CARGO_FLAGS_REL)

case-manager:
	$(CARGO) build -p i30ltz-case-manager $(CARGO_FLAGS_REL)

hardware-dash:
	$(CARGO) build -p i30ltz-hardware-dash $(CARGO_FLAGS_REL)

drive-scan:
	$(CARGO) build -p drivescan $(CARGO_FLAGS_REL)

report-gen:
	$(CARGO) build -p reportgen $(CARGO_FLAGS_REL)

# ── QUALITY ─────────────────────────────────────────────────
check:
	$(CARGO) check --workspace

fmt:
	$(CARGO) fmt --all

clippy:
	$(CARGO) clippy --workspace -- -D warnings

test:
	$(CARGO) test --workspace

# ── INSTALL ─────────────────────────────────────────────────
install: release
	@echo "[ i30LTZ ] Installing to $(INSTALL_PREFIX)..."
	install -d $(BIN_DIR) $(ASSETS_DIR) $(CONFIG_DIR) $(DATA_DIR)

	# Binaries
	install -m 755 target/release/i30ltz-shell    $(BIN_DIR)/i30ltz-shell
	install -m 755 target/release/mad-it           $(BIN_DIR)/mad-it
	install -m 755 target/release/i30cm            $(BIN_DIR)/i30cm
	install -m 755 target/release/i30ltz-hwdash    $(BIN_DIR)/i30ltz-hwdash
	install -m 755 target/release/drivescan        $(BIN_DIR)/drivescan
	install -m 755 target/release/reportgen        $(BIN_DIR)/reportgen

	# Assets
	cp -r assets/   $(ASSETS_DIR)/
	cp -r config/   $(CONFIG_DIR)/

	# Scripts
	install -m 755 scripts/i30ltz-launch.sh       /usr/local/bin/i30ltz

	@echo "[ i30LTZ ] Install complete. Run: i30ltz"

# ── UNINSTALL ───────────────────────────────────────────────
uninstall:
	@echo "[ i30LTZ ] Removing binaries..."
	rm -f $(BIN_DIR)/i30ltz-shell $(BIN_DIR)/mad-it $(BIN_DIR)/i30cm
	rm -f $(BIN_DIR)/i30ltz-hwdash $(BIN_DIR)/drivescan $(BIN_DIR)/reportgen
	rm -f /usr/local/bin/i30ltz
	@echo "[ i30LTZ ] Uninstall complete. Data preserved at $(DATA_DIR)."

# ── CLEAN ───────────────────────────────────────────────────
clean:
	$(CARGO) clean
	@echo "[ i30LTZ ] Clean complete."

# ── HELP ────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  i30LTZ Recovery OS — Build System v0.1.0 | 2026-09-26"
	@echo "  ────────────────────────────────────────────────────────"
	@echo "  make dev            Build all (dev, fast recompile)"
	@echo "  make release        Build all (release, stripped, optimized)"
	@echo "  make shell          Build only: i30ltz-shell (Slint UI)"
	@echo "  make mad-it         Build only: MAD IT AI core"
	@echo "  make case-manager   Build only: i30cm CLI"
	@echo "  make hardware-dash  Build only: hardware dashboard"
	@echo "  make drive-scan     Build only: drivescan tool"
	@echo "  make report-gen     Build only: reportgen tool"
	@echo "  make check          Cargo check (no binaries)"
	@echo "  make fmt            Format all source"
	@echo "  make clippy         Lint all source"
	@echo "  make test           Run all tests"
	@echo "  make install        Install to $(INSTALL_PREFIX)"
	@echo "  make uninstall      Remove installed binaries"
	@echo "  make clean          Remove build artifacts"
	@echo ""
