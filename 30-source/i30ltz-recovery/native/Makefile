SHELL := /bin/bash
CARGO ?= cargo
PREFIX ?= /opt/i30ltz
DESTDIR ?=
BINARIES := i30ltz-shell mad-it i30cm i30ltz-hwdash drivescan reportgen
.DEFAULT_GOAL := dev
.PHONY: all dev release check fmt clippy test smoke install install-check uninstall clean help shell mad-it case-manager hardware-dash drive-scan report-gen
all: dev
dev:
	$(CARGO) build --workspace --locked
release:
	$(CARGO) build --workspace --release --locked
check:
	$(CARGO) check --workspace --all-targets --locked
fmt:
	$(CARGO) fmt --all -- --check
clippy:
	$(CARGO) clippy --workspace --all-targets --locked -- -D warnings
test:
	$(CARGO) test --workspace --locked
smoke: dev
	python3 scripts/check-scaffold.py
shell:
	$(CARGO) build --locked -p i30ltz-shell
mad-it:
	$(CARGO) build --locked -p mad-it
case-manager:
	$(CARGO) build --locked -p i30ltz-case-manager
hardware-dash:
	$(CARGO) build --locked -p i30ltz-hardware-dash
drive-scan:
	$(CARGO) build --locked -p drivescan
report-gen:
	$(CARGO) build --locked -p reportgen
install: release
	install -d "$(DESTDIR)$(PREFIX)/bin" "$(DESTDIR)$(PREFIX)/config" "$(DESTDIR)/usr/local/bin"
	for binary in $(BINARIES); do install -m 755 "target/release/$$binary" "$(DESTDIR)$(PREFIX)/bin/$$binary"; done
	if [[ ! -e "$(DESTDIR)$(PREFIX)/config/i30ltz.toml" ]]; then install -m 644 config/i30ltz.toml "$(DESTDIR)$(PREFIX)/config/i30ltz.toml"; fi
	install -m 755 scripts/i30ltz-launch.sh "$(DESTDIR)/usr/local/bin/i30ltz"
uninstall:
	for binary in $(BINARIES); do rm -f -- "$(DESTDIR)$(PREFIX)/bin/$$binary"; done
	rm -f -- "$(DESTDIR)/usr/local/bin/i30ltz"
clean:
	$(CARGO) clean
help:
	@printf '%s\n' 'Native workspace scaffold — application features are not implemented.' 'make dev/check/test/clippy/smoke/release/install/uninstall/clean' 'Staged installation: make install DESTDIR=/absolute/staging/path' 'Launcher defaults to /opt/i30ltz; set I30LTZ_PREFIX for a custom install prefix.'

install-check:
	python3 scripts/check-install.py
